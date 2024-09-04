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

test "route" {
  let router : @http.Router = @http.Router(
    [
      Routed(
        "/hello",
        @types.Get,
        fn(_request : @http.Request) {
          @http.Response::{
            status: 200,
            headers: {  },
            body: { content: [b"Hello!"].iter(), trailers: fn() { Ok({  }) } },
          }
          |> Ok
        },
      ),
      Scoped(
        "/api",
        [],
        [
          @http.Routed(
            "/v1",
            @types.Get,
            fn(_request : @http.Request) {
              @http.Response::{
                status: 200,
                headers: {  },
                body: {
                  content: [b"API v1"].iter(),
                  trailers: fn() { Ok({  }) },
                },
              }
              |> Ok
            },
          ),
          Routed(
            "/v2",
            @types.Get,
            fn(_request : @http.Request) {
              @http.Response::{
                status: 200,
                headers: {  },
                body: {
                  content: [b"API v2"].iter(),
                  trailers: fn() { Ok({  }) },
                },
              }
              |> Ok
            },
          ),
          Routed(
            "/v3/:user/:role",
            @types.Get,
            fn(request : @http.Request) {
              let user = request.context.get("user").or("unknown user")
              let role = request.context.get("role").or("unknown role")
              let user_bytes = Bytes::new(user.length())
              user
              .iter()
              .eachi(fn { i, c => user_bytes[i] = c.to_int().to_byte() })
              let role_bytes = Bytes::new(role.length())
              role
              .iter()
              .eachi(fn { i, c => role_bytes[i] = c.to_int().to_byte() })
              @http.Response::{
                status: 200,
                headers: {  },
                body: {
                  content: [b"API v3:", user_bytes, b":", role_bytes].iter(),
                  trailers: fn() { Ok({  }) },
                },
              }
              |> Ok
            },
          ),
        ],
      ),
    ],
  )
  let handler = router.to_handler(
    not_found=fn() {
      {
        status: 404,
        headers: {  },
        body: { content: [b"Not found"].iter(), trailers: fn() { Ok({  }) } },
      }
    },
  )
  let response = (handler.0)(
    {
      path: "/hello",
      query: "",
      fragment: "",
      context: {  },
      method: @types.Get,
      scheme: None,
      authority: None,
      headers: {  },
      body: { content: [].iter(), trailers: fn() { Ok({  }) } },
    },
  )
  inspect!(
    response.unwrap().body.content.flat_map(Bytes::iter)
    |> utf8
    |> Iter::map(Char::to_string)
    |> Iter::collect
    |> Array::join(""),
    content="Hello!",
  )
  let response = (handler.0)(
    {
      path: "/api/v1",
      query: "",
      fragment: "",
      context: {  },
      method: @types.Get,
      scheme: None,
      authority: None,
      headers: {  },
      body: { content: [].iter(), trailers: fn() { Ok({  }) } },
    },
  )
  inspect!(
    response.unwrap().body.content.flat_map(Bytes::iter)
    |> utf8
    |> Iter::map(Char::to_string)
    |> Iter::collect
    |> Array::join(""),
    content="API v1",
  )
  let response = (handler.0)(
    {
      path: "/api/v2",
      query: "",
      fragment: "",
      context: {  },
      method: @types.Get,
      scheme: None,
      authority: None,
      headers: {  },
      body: { content: [].iter(), trailers: fn() { Ok({  }) } },
    },
  )
  inspect!(
    response.unwrap().body.content.flat_map(Bytes::iter)
    |> utf8
    |> Iter::map(Char::to_string)
    |> Iter::collect
    |> Array::join(""),
    content="API v2",
  )
  let response = (handler.0)(
    {
      path: "/api/v3/alice/admin",
      query: "",
      fragment: "",
      context: {  },
      method: @types.Get,
      scheme: None,
      authority: None,
      headers: {  },
      body: { content: [].iter(), trailers: fn() { Ok({  }) } },
    },
  )
  inspect!(
    response.unwrap().body.content.flat_map(Bytes::iter)
    |> utf8
    |> Iter::map(Char::to_string)
    |> Iter::collect
    |> Array::join(""),
    content="API v3:alice:admin",
  )
  let response = (handler.0)(
    {
      path: "/whatever",
      query: "",
      fragment: "",
      context: {  },
      method: @types.Get,
      scheme: None,
      authority: None,
      headers: {  },
      body: { content: [].iter(), trailers: fn() { Ok({  }) } },
    },
  )
  inspect!(
    response.unwrap().body.content.flat_map(Bytes::iter)
    |> utf8
    |> Iter::map(Char::to_string)
    |> Iter::collect
    |> Array::join(""),
    content="Not found",
  )
}

pub fn utf8(bytes : Iter[Byte]) -> Iter[Char] {
  Iter::new(
    fn(f) {
      let mut len = 0
      let mut char = 0
      for byte in bytes {
        let b = byte.to_int()
        if len == 0 {
          if b < 0b1100_0000 {
            match f(Char::from_int((char << 6) | b)) {
              IterEnd => break IterEnd
              IterContinue => continue
            }
          } else if b < 0b1110_0000 {
            char = b & 0b11111
            len = 1
          } else if b < 0b1111_0000 {
            char = b & 0b1111
            len = 2
          } else if b < 0b1111_1000 {
            char = b & 0b111
            len = 3
          } else {
            break IterEnd
          }
        } else if (b >> 6) == 0b10 {
          char = (char << 6) | (b & 0b111111)
          len -= 1
          if len == 0 {
            match f(Char::from_int(char)) {
              IterEnd => break IterEnd
              IterContinue => {
                char = 0
                continue
              }
            }
          }
        } else {
          break IterEnd
        }
      } else {
        IterContinue
      }
    },
  )
}
