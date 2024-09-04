// Copyright 2024 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

pub struct Request {
  context : Map[String, String]
  method : @types.Method
  scheme : @types.Scheme?
  authority : String?
  path : String
  query : String
  fragment : String
  headers : Map[String, Array[Bytes]]
  body : Body
}

pub fn request(
  authority : String?,
  ~path : String = "/",
  ~method : @types.Method = Get,
  ~query : String = "",
  ~fragment : String = "",
  ~scheme : @types.Scheme? = None,
  ~headers : Map[String, Array[Bytes]] = {  },
  ~body : Body = { content: [].iter(), trailers: fn() { Ok({  }) } },
  ~context : Map[String, String] = {  }
) -> Request {
  { context, method, scheme, authority, path, query, fragment, headers, body }
}

pub struct Response {
  status : UInt
  headers : Map[String, Array[Bytes]]
  body : Body
}

pub fn response(
  ~status : UInt = 200,
  ~headers : Map[String, Array[Bytes]] = {  },
  ~body : Body = { content: [].iter(), trailers: fn() { Ok({  }) } }
) -> Response {
  { status, headers, body }
}

/// Represents a body of an HTTP request or response.
/// 
/// The content can only be consumed once.
/// 
/// The trailers are only available after the content has been fully consumed.
/// 
/// The body of the request should be consumed
pub struct Body {
  content : Iter[Bytes]
  trailers : () -> Result[Map[String, Array[Bytes]], @types.ErrorCode]
}

pub fn json(self : Body) -> Json!@json.ParseError {
  let json = Buffer::new()
  self.content.flat_map(Bytes::iter).iter()
  |> @utils.decode_utf8()
  |> Iter::each(fn(ch) { json.write_char(ch) })
  @json.parse!(json.to_string())
}

pub fn text(self : Body) -> String {
  self.content.flat_map(Bytes::iter).iter()
  |> @utils.decode_utf8()
  |> @utils.iter_to_string
}

pub type HTTPHandler (Request) -> Result[Response, @types.ErrorCode]

pub type Middleware (HTTPHandler) -> HTTPHandler

pub type Router Array[Route]

pub enum Route {
  Routed(String, @types.Method, HTTPHandler)
  Scoped(String, Array[Middleware], Router)
}

pub fn to_handler(
  self : Router,
  ~not_found : () -> Response = fn() {
    Response::{
      status: 404,
      headers: {  },
      body: { content: Iter::empty(), trailers: fn() { Ok({  }) } },
    }
  }
) -> HTTPHandler {
  fn match_handler(router : Route, request : Request) -> String? {
    let pmatch = match router {
      Routed(str, method, _) => {
        if request.method != method {
          return None
        }
        str
      }
      Scoped(str, _, _) => str
    }
    let paths = request.path.split("/").collect()
    let pmatch = pmatch.split("/").collect()
    let context = {  }
    loop paths[:], pmatch[:] {
      [], [] => {
        context.each(fn(k, v) { request.context[k] = v })
        Some("/")
      }
      [], [_, ..] => None
      [head, .. as rest], [] => {
        context.each(fn(k, v) { request.context[k] = v })
        Some(["", head, ..rest].join("/"))
      }
      [head, .. as rest], [phead, .. as prest] =>
        if phead.starts_with(":") {
          context[phead.substring(start=1)] = head
          continue rest, prest
        } else if phead == "*" {
          continue rest, prest
        } else if head != phead {
          None
        } else {
          continue rest, prest
        }
    }
  }

  HTTPHandler(
    fn {
      request =>
        for router in self._ {
          match match_handler(router, request) {
            None => continue
            Some(path) =>
              match router {
                Routed(_, _, handler) => break (handler._)({ ..request, path, })
                Scoped(_, middlewares, routers) => {
                  let handler = routers |> to_handler(~not_found)
                  let handler = middlewares.rev_fold(
                    init=handler,
                    fn { handler, middleware => (middleware._)(handler) },
                  )
                  break (handler._)({ ..request, path, })
                }
              }
          }
        } else {
          not_found() |> Ok
        }
    },
  )
}

pub fn and_then(self : Middleware, other : Middleware) -> Middleware {
  fn {
    request => {
      let Middleware(self) = self
      let Middleware(other) = other
      request |> self |> other
    }
  }
}

pub fn serve(
  self : HTTPHandler
) -> (@types.IncomingRequest, @types.ResponseOutparam) -> Unit {
  fn(incoming, outparam) {
    let path_with_query = incoming.path_with_query().or("").split("?")
    let query_with_fragment = path_with_query
      .drop(1)
      .collect()
      .join("?")
      .split("#")
    let headers = @utils.use(
      incoming.headers(),
      fn(headers) {
        let map : Map[String, Array[Bytes]] = {  }
        headers
        .entries()
        .each(
          fn {
            (str, value) =>
              match map[str] {
                Some(values) => values.push(value)
                None => map[str] = [value]
              }
          },
        )
        map
      },
    )
    let length = headers["content-length"].map(
      fn(bytes) {
        let buffer = Buffer::new()
        bytes[0].iter()
        |> @utils.decode_utf8()
        |> Iter::each(fn(char) { buffer.write_char(char) })
        @strconv.parse_int?(buffer.to_string()).unwrap()
      },
    )
    let request = {
      context: {  },
      method: incoming.method(),
      scheme: incoming.scheme(),
      authority: incoming.authority(),
      path: path_with_query.take(1).collect().join(""),
      query: query_with_fragment.take(1).collect().join(""),
      fragment: query_with_fragment.drop(1).collect().join("#"),
      headers,
      body: parse_body(
        incoming.consume().unwrap(),
        length,
        fn() { incoming.drop() },
      ),
    }
    let response = match (self._)(request) {
      Ok(response) => response
      Err(code) => {
        outparam.set(Err(code))
        return
      }
    }
    let headers = @types.fields()
    response.headers.each(fn(k, v) { headers.set(k, v) |> ignore })
    let outgoing_response = @types.outgoing_response(headers)
    outgoing_response.set_status_code(response.status) |> ignore
    let body = outgoing_response.body().unwrap()
    outparam.set(Ok(outgoing_response)) |> ignore
    @utils.use(
      body.write().unwrap(),
      fn(stream) { @io.write(response.body.content, stream) },
    )
    let trailers = @types.fields()
    match (response.body.trailers)() {
      Ok(trailers) => trailers.each(fn(k, v) { trailers.set(k, v) |> ignore })
      Err(_) => () // nothing we can do
    }
    body.finish(Some(trailers)) |> ignore
  }
}

pub let client : HTTPHandler = HTTPHandler(
  fn {
    request => {
      let headers = @types.fields()
      request.headers.each(fn(k, v) { headers.set(k, v) |> ignore })
      let outgoing_request = @types.outgoing_request(headers)
      outgoing_request.set_method(request.method) |> ignore
      outgoing_request.set_scheme(request.scheme) |> ignore
      outgoing_request.set_authority(request.authority) |> ignore
      let path = request.path +
        if request.query.is_empty() { "" } else { "?" + request.query } +
        if request.fragment.is_empty() { "" } else { "#" + request.fragment }
      outgoing_request.set_path_with_query(Some(path)) |> ignore
      let body = outgoing_request.body().unwrap()
      let future_response = match
        @outgoingHandler.handle(outgoing_request, None) {
        Ok(response) => response
        Err(code) => return Err(code)
      }
      @utils.use(
        body.write().unwrap(),
        fn(stream) { @io.write(request.body.content, stream) },
      )
      let trailers = @types.fields()
      match (request.body.trailers)() {
        Ok(trailers) => trailers.each(fn(k, v) { trailers.set(k, v) |> ignore })
        Err(_) => () // nothing we can do
      }
      body.finish(Some(trailers)) |> ignore
      @utils.use(future_response.subscribe(), @poll.Pollable::block)
      let response = match future_response.get().unwrap().unwrap() {
        Ok(response) => response
        Err(err) => return Err(err)
      }
      let headers = {
        let map : Map[String, Array[Bytes]] = {  }
        let headers = response.headers()
        headers
        .entries()
        .each(
          fn {
            (str, value) =>
              match map[str.to_lower()] {
                Some(values) => values.push(value)
                None => map[str.to_lower()] = [value]
              }
          },
        )
        headers.drop()
        map
      }
      let length = headers["content-length"].map(
        fn(bytes) {
          bytes[0].iter()
          |> @utils.decode_utf8()
          |> @utils.iter_to_string()
          |> @strconv.parse_int?()
          |> Result::unwrap()
        },
      )
      let resp = Response::{
        status: response.status(),
        headers: @utils.use(
          response.headers(),
          fn(headers) {
            let map : Map[String, Array[Bytes]] = {  }
            headers
            .entries()
            .each(
              fn {
                (str, value) =>
                  match map[str] {
                    Some(values) => values.push(value)
                    None => map[str] = [value]
                  }
              },
            )
            map
          },
        ),
        body: parse_body(
          response.consume().unwrap(),
          length,
          fn() { response.drop() },
        ),
      }
      resp |> Ok
    }
  },
)

fn parse_body(
  incomingBody : @types.IncomingBody,
  length : Int?,
  drop : () -> Unit
) -> Body {
  let read = { val: Some(incomingBody.stream().unwrap()) }
  let trailers = { val: None }
  Body::{
    content: Iter::new(
      fn(f) {
        let body_stream = match read.val {
          Some(stream) => stream
          None => return IterEnd
        }
        let length = length.or(@int.max_value)
        loop length, body_stream.blocking_read(4096) {
          len, Ok(bytes) =>
            match f(bytes) {
              IterEnd => {
                body_stream.drop()
                read.val = None
                return IterEnd
              }
              IterContinue => {
                let next = len - bytes.length()
                if next > 0 {
                  continue next, body_stream.blocking_read(4096)
                } else {
                  body_stream.drop()
                  read.val = None
                  return IterContinue
                }
              }
            }
          _, Err(@streams.Closed) => {
            body_stream.drop()
            read.val = None
            IterContinue
          }
          _, Err(_) => {
            body_stream.drop()
            read.val = None
            return IterEnd
          }
        }
      },
    ),
    trailers: fn() {
      match read.val {
        Some(stream) => stream.drop()
        None => ()
      }
      match trailers.val {
        Some(map) => map
        None => {
          let future_trailers = incomingBody.finish()
          @utils.use(future_trailers.subscribe(), @poll.Pollable::block)
          let map : Map[String, Array[Bytes]] = {  }
          trailers.val = Some(Ok(map))
          match future_trailers.get().unwrap().unwrap() {
            Ok(Some(trailers)) => {
              trailers
              .entries()
              .each(
                fn {
                  (str, value) =>
                    match map[str] {
                      Some(values) => values.push(value)
                      None => map[str] = [value]
                    }
                },
              )
              trailers.drop()
            }
            Ok(None) => ()
            Err(error) => {
              trailers.val = Some(Err(error))
              return Err(error)
            }
          }
          future_trailers.drop()
          drop()
          Ok(map)
        }
      }
    },
  }
}
