defmodule Photon.HTTP do
  def parse({error, state}) do
    {error, state}
  end

  def parse(state \\ %{}) do
    cond do
      !state[:step] ->
        parse(read_path(state))

      state.step == :headers ->
        parse(read_headers(state))

      state.step == :body ->
        state =
          case state.headers["connection"] do
            "upgrade" -> Map.merge(state, %{connection: :upgrade})
            "keep-alive" -> Map.merge(state, %{connection: :keepalive})
            _ -> Map.merge(state, %{connection: :close})
          end

        cond do
          state.method in ["HEAD", "OPTIONS", "GET"] ->
            Map.merge(state, %{step: :next})

          true ->
            state
        end
    end
  end

  def parse_response({error, state}) do
    {error, state}
  end

  def parse_response(state \\ %{}) do
    cond do
      !state[:step] ->
        parse_response(read_response_code(state))

      state.step == :headers ->
        parse_response(read_headers(state))

      state.step == :body ->
        state =
          case state.headers["connection"] do
            "upgrade" -> Map.merge(state, %{connection: :upgrade})
            "keep-alive" -> Map.merge(state, %{connection: :keepalive})
            _ -> Map.merge(state, %{connection: :close})
          end

        cond do
          # TODO: get length of reply here and parse or skip
          state.connection == :upgrade -> Map.merge(state, %{step: :next})
          true -> state
        end
    end
  end

  def read_path(state) do
    case :binary.split(state.buf, "\r\n") do
      [request, buf] ->
        [method, path, _] = String.split(request, " ")

        {path, query} =
          case :binary.split(path, "?") do
            [path] -> {path, nil}
            [path, query] -> {path, query}
          end

        Map.merge(state, %{method: method, path: path, query: query, buf: buf, step: :headers})

      _ ->
        {:partial, state}
    end
  end

  def read_response_code(state) do
    case :binary.split(state.buf, "\r\n") do
      [response, buf] ->
        [http11, rest] = :binary.split(response, " ")
        [status_code, status_text] = :binary.split(rest, " ")

        Map.merge(state, %{
          status_code: :erlang.binary_to_integer(status_code),
          status_text: status_text,
          buf: buf,
          step: :headers
        })

      _ ->
        {:partial, state}
    end
  end

  def read_headers(state) do
    case :binary.split(state.buf, "\r\n\r\n") do
      [headers, buf] ->
        headers = String.split(headers, "\r\n")

        headers_list =
          Enum.map(headers, fn line ->
            [k, v] = :binary.split(line, ": ")
            k = String.downcase(k)

            v =
              case {k, v} do
                {"connection", "Keep-Alive"} -> "keep-alive"
                {"connection", "Close"} -> "close"
                {"connection", "Upgrade"} -> "upgrade"
                {_k, v} -> v
              end

            %{key: k, value: v}
          end)

        headers = Enum.into(headers_list, %{}, &{&1.key, &1.value})
        Map.merge(state, %{headers: headers, headers_list: headers_list, buf: buf, step: :body})

      _ ->
        {:partial, state}
    end
  end

  def read_body_all(state) do
    r = state.request

    cl =
      Map.fetch!(r.headers, "content-length")
      |> :erlang.binary_to_integer()

    to_recv = cl - byte_size(r.buf)

    bin =
      if to_recv > 0 do
        {:ok, bin} = :gen_tcp.recv(state.socket, to_recv)
        state = put_in(state, [:request, :buf], "")
        {state, r.buf <> bin}
      else
        <<bin::binary-size(cl), buf::binary>> = r.buf
        state = put_in(state, [:request, :buf], buf)
        {state, bin}
      end
  end

  def read_body_all_json(state, json_args \\ [{:labels, :attempt_atom}]) do
    {state, bin} = read_body_all(state)
    json = JSX.decode!(bin, json_args)
    {state, json}
  end

  def build_headers(headers \\ %{}) do
    Enum.reduce(headers, "", &(&2 <> "#{elem(&1, 0)}: #{elem(&1, 1)}\r\n"))
    |> String.trim()
  end

  def build_status_text(status_code, status_text \\ nil) do
    cond do
      status_text -> status_text
      status_code == 200 -> "OK"
      status_code == 302 -> "Found"
      true -> "OK"
    end
  end

  def build_request(request) do
    headers = build_headers(request[:headers] || %{})
    "#{request.method} #{request.path} HTTP/1.1\r\n#{headers}\r\n\r\n#{request[:body]}"
  end

  def build_response(response) do
    headers = build_headers(response[:headers] || %{})
    status_text = build_status_text(response.status_code, response[:status_text])
    "HTTP/1.1 #{response.status_code} #{status_text}\r\n#{headers}\r\n\r\n#{response[:body]}"
  end

  def build_header_date() do
    dt = DateTime.utc_now()
    day_of_week = Calendar.ISO.day_of_week(dt.year, dt.month, dt.day)

    day_of_week =
      case day_of_week do
        1 -> "Mon"
        2 -> "Tue"
        3 -> "Wed"
        4 -> "Thu"
        5 -> "Fri"
        6 -> "Sat"
        7 -> "Sun"
      end

    month =
      case dt.month do
        1 -> "Jan"
        2 -> "Feb"
        3 -> "Mar"
        4 -> "Apr"
        5 -> "May"
        6 -> "Jun"
        7 -> "Jul"
        8 -> "Aug"
        9 -> "Sep"
        10 -> "Oct"
        11 -> "Nov"
        12 -> "Dec"
      end

    "#{day_of_week}, #{dt.day} #{month} #{dt.year} #{dt.hour}:#{dt.minute}:#{dt.second} GMT"
  end

  def parse_query(query) do
    String.split(query, "&")
    |> Enum.into(%{}, fn line ->
      [k, v] = :binary.split(line, "=")

      k =
        try do
          String.to_existing_atom(k)
        catch
          _, _ -> k
        end

      {k, v}
    end)
  end

  def sanitize_path(path) do
    dir =
      :filename.dirname(path)
      |> :re.replace("[^0-9A-Za-z\\-\\_\\/]", "", [:global, {:return, :binary}])

    filename =
      :filename.basename(path)
      |> :re.replace("[^0-9A-Za-z\\-\\_\\.]", "", [:global, {:return, :binary}])

    sanitize_path_1("#{dir}/#{filename}")
  end

  defp sanitize_path_1(path) do
    path = :binary.replace(path, "//", "/")

    case :binary.match(path, "//") do
      :nomatch ->
        case path do
          <<"/", path::binary>> -> path
          _ -> path
        end

      _ ->
        sanitize_path_1(path)
    end
  end

  def add_cors(headers) do
    Map.merge(headers, %{
      "Access-Control-Allow-Origin" => "*",
      "Access-Control-Allow-Methods" => "HEAD, OPTIONS, PATH, GET, POST, PUT, DELETE",
      "Access-Control-Allow-Headers" =>
        "Cache-Control, Pragma, Origin, Authorization, Content-Type, X-Requested-With, Extra, Filename"
    })
  end

  def add_date(headers) do
    Map.merge(headers, %{
      "Date" => build_header_date()
    })
  end

  def add_content_length(headers, body) do
    Map.merge(headers, %{
      "Content-Length" => "#{byte_size(body)}"
    })
  end

  def add_connection(headers, r) do
    Map.merge(headers, %{
      "Connection" =>
        if r.connection == :close do
          "close"
        else
          "keep-alive"
        end
    })
  end

  def can_accept_gzip(headers) do
    Map.get(headers, "accept-encoding", "")
    |> :binary.match("gzip")
    |> case do
      :nomatch -> false
      _ -> true
    end
  end

  def is_cached(headers, etag) do
    cache_etag = headers["if-none-match"]
    cache_etag == etag
  end

  def build_cors_response(request, body, extra_headers \\ %{}) do
    headers =
      %{"Content-Type": "application/json; charset=utf-8"}
      |> add_cors()
      |> add_date()
      |> add_connection(request)

    body =
      cond do
        is_map(body) or is_list(body) -> JSX.encode!(body)
        true -> body
      end

    headers = Map.put(headers, "Content-Length", "#{byte_size(body)}")
    headers = Map.merge(headers, extra_headers)

    Photon.HTTP.build_response(%{status_code: 200, headers: headers, body: body})
  end

  def build_cached_response(state, map) do
    headers =
      %{
        "Content-Type" => "text/html; charset=utf-8"
      }
      |> add_date()
      |> add_connection(state.request)

    h = state.request.headers
    can_gzip = can_accept_gzip(h)

    cond do
      can_gzip and is_cached(h, map.crc32_gzipped) ->
        headers =
          Map.merge(headers, %{"Etag" => map.crc32_gzipped})
          |> add_content_length("")

        reply = build_response(%{status_code: 304, headers: headers})
        :ok = :gen_tcp.send(state.socket, reply)
        state

      can_gzip ->
        headers =
          Map.merge(headers, %{"Content-Encoding" => "gzip", "Etag" => map.crc32_gzipped})
          |> add_content_length(map.gzipped)

        reply = build_response(%{status_code: 200, headers: headers, body: map.gzipped})
        :ok = :gen_tcp.send(state.socket, reply)
        state

      !can_gzip and is_cached(h, map.crc32_bin) ->
        headers =
          Map.merge(headers, %{"Etag" => map.crc32_bin})
          |> add_content_length("")

        reply = build_response(%{status_code: 304, headers: headers})
        :ok = :gen_tcp.send(state.socket, reply)
        state

      !can_gzip ->
        headers =
          Map.merge(headers, %{"Etag" => map.crc32_bin})
          |> add_content_length(map.bin)

        reply = build_response(%{status_code: 200, headers: headers, body: map.bin})
        :ok = :gen_tcp.send(state.socket, reply)
        state
    end
  end
end
