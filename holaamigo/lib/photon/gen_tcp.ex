defmodule Photon.GenTCP do
  def listen(port, opts \\ []) do
    {:ok, lsocket} = :gen_tcp.listen(port, opts)
    lsocket
  end

  def listen_highthruput(port, opts \\ []) do
    buffer = 8_388_608

    basic_opts = [
      {:inet_backend, :socket},
      {:nodelay, true},
      {:active, false},
      {:reuseaddr, true},
      {:exit_on_close, false},
      :binary,
      {:buffer, buffer}
    ]

    socket = listen(port, basic_opts ++ opts)
    {:ok, proplist} = :inet.getopts(socket, [:buffer, :recbuf, :sndbuf])
    %{buffer: b, recbuf: r, sndbuf: s} = :maps.from_list(proplist)
    if b != buffer, do: IO.puts("Photon.GenTCP: wanted buffer #{buffer} got #{b}")
    socket
  end

  def connect(ip, port, opts \\ [], transport \\ :gen_tcp, timeout \\ 8_000) do
    buffer = 131_072

    basic_opts = [
      # {:inet_backend, :socket}, #not supported for SSL? :()
      {:nodelay, true},
      {:active, false},
      {:reuseaddr, true},
      {:exit_on_close, false},
      :binary,
      {:buffer, buffer}
    ]

    {:ok, socket} = transport.connect(ip, port, basic_opts ++ opts, timeout)
    socket
  end

  def connect_url(url, opts \\ []) do
    uri = URI.parse(url)

    port =
      cond do
        uri.port -> uri.port
        uri.scheme in ["http", "ws"] -> 80
        uri.scheme in ["https", "wss"] -> 443
      end

    if uri.scheme in ["https", "wss"] do
      ssl_opts = [
        {:server_name_indication, '#{URI.parse(url).host}'},
        {:verify, :verify_peer},
        {:depth, 99},
        {:cacerts, :certifi.cacerts()},
        # {:verify_fun, verifyFun},
        {:partial_chain, &partial_chain/1},
        {:customize_hostname_check,
         [{:match_fun, :public_key.pkix_verify_hostname_match_fun(:https)}]}
      ]

      connect('#{uri.host}', port, ssl_opts ++ opts, :ssl)
    else
      connect('#{uri.host}', port, opts)
    end
  end

  # Misc
  def setopts(socket, opts) when is_port(socket) do
    :inet.setopts(socket, opts)
  end

  def setopts(socket, opts) when is_tuple(socket) do
    :ssl.setopts(socket, opts)
  end

  def send(socket, bin) when is_port(socket) do
    :gen_tcp.send(socket, bin)
  end

  def send(socket, bin) when is_tuple(socket) do
    :ssl.send(socket, bin)
  end

  # SSL Pin
  def partial_chain(certs) do
    certs =
      :lists.reverse(
        Enum.map(certs, fn cert -> {cert, :public_key.pkix_decode_cert(cert, :otp)} end)
      )

    case find(fn {_, cert} -> check_cert(decoded_cacerts(), cert) end, certs) do
      {:ok, trusted} -> {:trusted_ca, :erlang.element(1, trusted)}
      _ -> :unknown_ca
    end
  end

  defp find(fun, [h | t]) when is_function(fun) do
    case fun.(h) do
      true -> {:ok, h}
      false -> find(fun, t)
    end
  end

  defp find(_, []), do: :error

  defp check_cert(caCerts, cert) do
    publicKeyInfo = :hackney_ssl_certificate.public_key_info(cert)
    :lists.member(publicKeyInfo, caCerts)
  end

  defp decoded_cacerts() do
    :ct_expand.term(
      :lists.foldl(
        fn cert, acc ->
          dec = :public_key.pkix_decode_cert(cert, :otp)
          [:hackney_ssl_certificate.public_key_info(dec) | acc]
        end,
        [],
        :certifi.cacerts()
      )
    )
  end
end

defmodule Photon.GenTCPAcceptor do
  def start_link(port, module) when is_atom(module) do
    pid = :erlang.spawn_link(__MODULE__, :init, [port, module])
    {:ok, pid}
  end

  def start_link(ip, port, module) when is_atom(module) do
    pid = :erlang.spawn_link(__MODULE__, :init, [ip, port, module])
    {:ok, pid}
  end

  def init(port, module) do
    lsocket = Photon.GenTCP.listen_highthruput(port)
    state = %{ip: {0, 0, 0, 0}, port: port, lsocket: lsocket, module: module}
    accept_loop(state)
  end

  def init(ip, port, module) do
    lsocket = Photon.GenTCP.listen_highthruput(port, [{:ifaddr, ip}])
    state = %{ip: ip, port: port, lsocket: lsocket, module: module}
    accept_loop(state)
  end

  def accept_loop(state) do
    {:ok, socket} = :gen_tcp.accept(state.lsocket)

    pid = :erlang.spawn(state.module, :init, [%{ip: state.ip, port: state.port, socket: socket}])
    :ok = :gen_tcp.controlling_process(socket, pid)
    send(pid, :socket_ack)
    # :inet.setopts(socket, [{:active, :once}])

    accept_loop(state)
  end
end
