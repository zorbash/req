defmodule Req.RequestTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    [bypass: bypass, url: "http://localhost:#{bypass.port}"]
  end

  test "low-level API", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    request = Req.Request.build(:get, c.url <> "/ok")
    assert {:ok, %{status: 200, body: "ok"}} = Req.Request.run(request)
  end

  test "simple request step", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    request =
      Req.Request.build(:get, c.url <> "/not-found")
      |> Req.Request.prepend_request_steps([
        fn request ->
          put_in(request.url.path, "/ok")
        end
      ])

    assert {:ok, %{status: 200, body: "ok"}} = Req.Request.run(request)
  end

  test "request step returns response", c do
    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_request_steps([
        fn request ->
          {request, %Req.Response{status: 200, body: "from cache"}}
        end
      ])
      |> Req.Request.prepend_response_steps([
        fn {request, response} ->
          {request, update_in(response.body, &(&1 <> " - updated"))}
        end
      ])

    assert {:ok, %{status: 200, body: "from cache - updated"}} = Req.Request.run(request)
  end

  test "request step returns exception", c do
    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_request_steps([
        fn request ->
          {request, RuntimeError.exception("oops")}
        end
      ])
      |> Req.Request.prepend_error_steps([
        fn {request, exception} ->
          {request, update_in(exception.message, &(&1 <> " - updated"))}
        end
      ])

    assert {:error, %RuntimeError{message: "oops - updated"}} = Req.Request.run(request)
  end

  test "request step halts with response", c do
    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_request_steps([
        fn request ->
          {Req.Request.halt(request), %Req.Response{status: 200, body: "from cache"}}
        end,
        &unreachable/1
      ])
      |> Req.Request.prepend_response_steps([
        &unreachable/1
      ])
      |> Req.Request.prepend_error_steps([
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "from cache"}} = Req.Request.run(request)
  end

  test "request step halts with exception", c do
    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_request_steps([
        fn request ->
          {Req.Request.halt(request), RuntimeError.exception("oops")}
        end,
        &unreachable/1
      ])
      |> Req.Request.prepend_response_steps([
        &unreachable/1
      ])
      |> Req.Request.prepend_error_steps([
        &unreachable/1
      ])

    assert {:error, %RuntimeError{message: "oops"}} = Req.Request.run(request)
  end

  test "simple response step", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_response_steps([
        fn {request, response} ->
          {request, update_in(response.body, &(&1 <> " - updated"))}
        end
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.Request.run(request)
  end

  test "response step returns exception", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_response_steps([
        fn {request, response} ->
          assert response.body == "ok"
          {request, RuntimeError.exception("oops")}
        end
      ])
      |> Req.Request.prepend_error_steps([
        fn {request, exception} ->
          {request, update_in(exception.message, &(&1 <> " - updated"))}
        end
      ])

    assert {:error, %RuntimeError{message: "oops - updated"}} = Req.Request.run(request)
  end

  test "response step halts with response", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_response_steps([
        fn {request, response} ->
          {Req.Request.halt(request), update_in(response.body, &(&1 <> " - updated"))}
        end,
        &unreachable/1
      ])
      |> Req.Request.prepend_error_steps([
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.Request.run(request)
  end

  test "response step halts with exception", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_response_steps([
        fn {request, response} ->
          assert response.body == "ok"
          {Req.Request.halt(request), RuntimeError.exception("oops")}
        end,
        &unreachable/1
      ])
      |> Req.Request.prepend_error_steps([
        &unreachable/1
      ])

    assert {:error, %RuntimeError{message: "oops"}} = Req.Request.run(request)
  end

  test "simple error step", c do
    Bypass.down(c.bypass)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_error_steps([
        fn {request, exception} ->
          assert exception.reason == :econnrefused
          {request, RuntimeError.exception("oops")}
        end
      ])

    assert {:error, %RuntimeError{message: "oops"}} = Req.Request.run(request)
  end

  test "error step returns response", c do
    Bypass.down(c.bypass)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_response_steps([
        fn {request, response} ->
          {request, update_in(response.body, &(&1 <> " - updated"))}
        end
      ])
      |> Req.Request.prepend_error_steps([
        fn {request, exception} ->
          assert exception.reason == :econnrefused
          {request, %Req.Response{status: 200, body: "ok"}}
        end,
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.Request.run(request)
  end

  test "error step halts with response", c do
    Bypass.down(c.bypass)

    request =
      Req.Request.build(:get, c.url <> "/ok")
      |> Req.Request.prepend_response_steps([
        &unreachable/1
      ])
      |> Req.Request.prepend_error_steps([
        fn {request, exception} ->
          assert exception.reason == :econnrefused
          {Req.Request.halt(request), %Req.Response{status: 200, body: "ok"}}
        end,
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "ok"}} = Req.Request.run(request)
  end

  ## Helpers

  defp unreachable(_) do
    raise "unreachable"
  end
end
