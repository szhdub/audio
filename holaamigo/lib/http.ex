defmodule Https do
  def init(state) do
    receive do
      :socket_ack -> :ok
    after
      3000 -> throw(:no_socket_passed)
    end

    IO.inspect("init ssl handshake")

    res =
      try do
        :ssl.handshake(state.socket, [
          {:verify, :verify_none},
          {:fail_if_no_peer_cert, false},
          #          {:cacertfile, "cacerts.pem"},
          {:certs_keys,
           [
             %{
               :certfile => "/etc/letsencrypt/live/holaamigo.gg/fullchain.pem",
               :keyfile => "/etc/letsencrypt/live/holaamigo.gg/privkey.pem"
             }
           ]}
        ])
      catch
        a, b ->
          IO.inspect({:exception, a, b, __STACKTRACE__})
      end

    #    IO.inspect({:ssl_handshake_result, res})
    {:ok, socket} = res
    state = Map.put(state, :request, %{buf: <<>>})
    state = Map.put(state, :socket, socket)
    :ok = :ssl.setopts(state.socket, [{:active, :once}])
    loop_http(state)
  end

  def loop_http(state) do
    receive do
      {:ssl, socket, bin} ->
        request = %{state.request | buf: state.request.buf <> bin}

        case Photon.HTTP.parse(request) do
          {:partial, request} ->
            state = put_in(state, [:request], request)
            :ssl.setopts(socket, [{:active, :once}])
            loop_http(state)

          request ->
            state = put_in(state, [:request], request)

            cond do
              request[:step] in [:next, :body] ->
                state = handle_http(state)

                if request[:connection] in [:close, :upgrade] do
                  :ssl.shutdown(socket, :write)
                else
                  {_, state} = pop_in(state, [:request, :step])
                  :ssl.setopts(socket, [{:active, :once}])
                  loop_http(state)
                end

              true ->
                :ssl.setopts(socket, [{:active, :once}])
                loop_http(state)
            end
        end

      {:ssl_closed, socket} ->
        :closed

      m ->
        IO.inspect("MultiServer: #{inspect(m)}")
    end
  end

  def cors_reponse(state, body, extra_headers \\ %{}, status_code \\ 200) do
    r = state.request

    headers = %{
      "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => "GET, POST, HEAD, PUT, DELETE",
      "Access-Control-Allow-Headers" =>
        "Cache-Control, Pragma, Origin, Authorization, Location, Content-Type, X-Requested-With, Extra",
      "Date" => Photon.HTTP.build_header_date(),
      "Content-Type" => "application/json; charset=utf-8",
      "Connection" =>
        if r.connection == :close do
          "close"
        else
          "keep-alive"
        end
    }

    {body, headers} =
      cond do
        !body ->
          {nil, headers}

        is_map(body) or is_list(body) ->
          body = JSX.encode!(body)
          headers = Map.put(headers, "Content-Length", "#{byte_size(body)}")
          {body, headers}

        true ->
          headers = Map.put(headers, "Content-Length", "#{byte_size(body)}")
          {body, headers}
      end

    headers = Map.merge(headers, extra_headers)

    reply = Photon.HTTP.build_response(%{status_code: 200, headers: headers, body: body})
  end

  def read_body_all(state) do
    r = state.request

    cl =
      Map.fetch!(r.headers, "content-length")
      |> :erlang.binary_to_integer()

    to_recv = cl - byte_size(r.buf)

    bin =
      if to_recv > 0 do
        {:ok, bin} = :ssl.recv(state.socket, to_recv)
        state = put_in(state, [:request, :buf], "")
        {state, r.buf <> bin}
      else
        <<bin::binary-size(cl), buf::binary>> = r.buf
        state = put_in(state, [:request, :buf], buf)
        {state, bin}
      end
  end

  def handle_http(state) do
    try do
      handle_http_0(state)
    catch
      a, b ->
        IO.inspect {:web_crashed, a, b}
        :ok = :ssl.send(state.socket, Photon.HTTP.build_cors_response("error", ""))
        :ssl.close(state.socket)
        :closed
    end
  end

  def handle_http_0(state) do
    r = state.request
    IO.inspect({r.method, r.path, r.query, r.headers["host"], r[:body]})
    # X-Api-Key
    # User pubkey, %{deposit: 0}
    # APIKey {key, owner}, %{create_job: true, delete_job: true, view_log: true}
    cond do
      r.method in ["OPTIONS", "HEAD"] ->
        :ok = :ssl.send(state.socket, Photon.HTTP.build_cors_response(r, ""))
        state

      # r.headers["upgrade"] == "websocket" and String.starts_with?(r.path, "/ws/panel") ->
      #    Shep.WSPanel.init(state)

      r.method == "POST" and r.path == "/messages" ->
        {state, body} = read_body_all(state)
        message = JSX.decode!(body)["message"]
        File.write!("message", message)
        IO.inspect({:got_body, message})

        q = :comsat_http.post("https://fourth-org-revenues-chevy.trycloudflare.com/", body)
        IO.inspect({:backend_reply, q})

        case q do
          {:ok, %{body: b}} ->
            :ok =
              :ssl.send(
                state.socket,
                cors_reponse(state, b, %{}, 200)
              )

          _ ->
            :ok =
              :ssl.send(
                state.socket,
                cors_reponse(state, "{'error': 'unknown'}", %{}, 200)
              )
        end

        state

      r.method == "GET" and r.path == "/" ->
        extraheaders = %{"Content-Type" => "text/html; charset=utf-8"}

        :ok =
          :ssl.send(
            state.socket,
            cors_reponse(state, File.read!("www/index.html"), extraheaders, 200)
          )

        state

      !!("/es/" <> f = r.path) and r.method == "GET" ->
        if Regex.match?(~r"^[a-z._0-9]*$", f) do
          :ok =
            :ssl.send(
              state.socket,
              Http.cors_reponse(state, File.read!("www/es/" <> f), %{}, 200)
            )
        else
          :ok = :ssl.send(state.socket, Http.cors_reponse(state, "error", %{}, 401))
        end

        state

      !!("/" <> f = r.path) and r.method == "GET" ->
        if Regex.match?(~r"^[a-z._0-9]*$", f) do
          :ok =
            :ssl.send(state.socket, Http.cors_reponse(state, File.read!("www/" <> f), %{}, 200))
        else
          :ok = :ssl.send(state.socket, Http.cors_reponse(state, "error", %{}, 401))
        end

        state

      true ->
        :ok = :ssl.send(state.socket, Http.cors_reponse(state, "unhandled", %{}, 401))

        IO.inspect({:unknown_http_request, r})
        state
    end
  end
end

defmodule Http do
  def init(state) do
    receive do
      :socket_ack -> :ok
    after
      3000 -> throw(:no_socket_passed)
    end

    state = Map.put(state, :request, %{buf: <<>>})
    :ok = :inet.setopts(state.socket, [{:active, :once}])
    loop_http(state)
  end

  def loop_http(state) do
    receive do
      {:tcp, socket, bin} ->
        request = %{state.request | buf: state.request.buf <> bin}

        case Photon.HTTP.parse(request) do
          {:partial, request} ->
            state = put_in(state, [:request], request)
            :inet.setopts(socket, [{:active, :once}])
            loop_http(state)

          request ->
            state = put_in(state, [:request], request)

            cond do
              request[:step] in [:next, :body] ->
                state = handle_http(state)

                if request[:connection] in [:close, :upgrade] do
                  :gen_tcp.shutdown(socket, :write)
                else
                  {_, state} = pop_in(state, [:request, :step])
                  :inet.setopts(socket, [{:active, :once}])
                  loop_http(state)
                end

              true ->
                :inet.setopts(socket, [{:active, :once}])
                loop_http(state)
            end
        end

      {:tcp_closed, socket} ->
        :closed

      m ->
        IO.inspect("MultiServer: #{inspect(m)}")
    end
  end

  def cors_reponse(state, body, extra_headers \\ %{}, status_code \\ 200) do
    r = state.request

    headers = %{
      "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => "GET, POST, HEAD, PUT, DELETE",
      "Access-Control-Allow-Headers" =>
        "Cache-Control, Pragma, Origin, Authorization, Location, Content-Type, X-Requested-With, Extra",
      "Date" => Photon.HTTP.build_header_date(),
      "Content-Type" => "application/json; charset=utf-8",
      "Connection" =>
        if r.connection == :close do
          "close"
        else
          "keep-alive"
        end
    }

    {body, headers} =
      cond do
        !body ->
          {nil, headers}

        is_map(body) or is_list(body) ->
          body = JSX.encode!(body)
          headers = Map.put(headers, "Content-Length", "#{byte_size(body)}")
          {body, headers}

        true ->
          headers = Map.put(headers, "Content-Length", "#{byte_size(body)}")
          {body, headers}
      end

    headers = Map.merge(headers, extra_headers)

    reply = Photon.HTTP.build_response(%{status_code: 200, headers: headers, body: body})
  end

  def handle_http(state) do
    r = state.request
    IO.inspect({r.method, r.path, r.query, r.headers["host"], r[:body]})
    # X-Api-Key
    # User pubkey, %{deposit: 0}
    # APIKey {key, owner}, %{create_job: true, delete_job: true, view_log: true}
    cond do
      r.method in ["OPTIONS", "HEAD"] ->
        :ok = :gen_tcp.send(state.socket, Photon.HTTP.build_cors_response(r, ""))
        state

      # r.headers["upgrade"] == "websocket" and String.starts_with?(r.path, "/ws/panel") ->
      #    Shep.WSPanel.init(state)

      r.method == "GET" and r.path == "/" ->
        :ok = :gen_tcp.send(state.socket, Http.cors_reponse(state, "index.html", %{}, 200))
        state

      r.method == "GET" and
          String.starts_with?(
            r.path,
            "/.well-known/acme-challenge/"
          ) ->
        IO.inspect("got challenge")

        :ok =
          :gen_tcp.send(
            state.socket,
            Http.cors_reponse(
              state,
              "",
              %{},
              200
            )
          )

        :gen_tcp.close(state.socket)

        state

      true ->
        IO.inspect({:unknown_http_request, r})
        state
    end
  end
end
