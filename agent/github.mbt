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

let wrong_request : @http.Response = @http.response(
  status=400,
  body={ content: [b"Wrong request"].iter(), trailers: fn() { Ok({  }) } },
)

let internal_error : @http.Response = @http.response(
  status=500,
  body={ content: [b"Internal error"].iter(), trailers: fn() { Ok({  }) } },
)

let github_api = "api.github.com"

/// Main handler for the agent
fn handler(~client : @http.HTTPHandler = @http.client) -> @http.HTTPHandler {
  fn(request : @http.Request) {
    let { headers, body, .. } : @http.Request = request
    let event = match headers {
      { "x-github-event": [event] } =>
        event.iter() |> @utils.decode_utf8 |> @utils.iter_to_string
      _ => {
        @io.eprintln("Error: x-github-event not found")
        return wrong_request |> Ok
      }
    }
    match event {
      "pull_request" =>
        try {
          body.json!()
        } catch {
          parse_error => {
            @io.eprintln("Error parsing json: \{parse_error}")
            (body.trailers)() |> ignore
            return wrong_request |> Ok
          }
        } else {
          {
            "action": String("opened" | "synchronize" as action),
            "repository": {
              "name": String(repository),
              "owner": { "login": String(owner) },
            },
            "installation": { "id": Number(installation) },
            "pull_request": { "number": Number(pull_request) },
          } =>
            try {
              let pull_request = pull_request.to_int64()
              @io.println(
                "\{owner}#\{repository}#\{pull_request} Event received for \{action}",
              )
              let token = create_installation_access_token!(
                installation.to_int().to_string(),
                client,
              )
              @io.println(
                "\{owner}#\{repository}#\{pull_request} Token signedoff",
              )
              let diff = get_pr_diff!(
                owner, repository, pull_request, token, client,
              )
              @io.println("\{owner}#\{repository}#\{pull_request} Fetched diff")
              let review = get_code_review_from_deepseek!(diff, client)
              @io.println(
                "\{owner}#\{repository}#\{pull_request} Fetched review",
              )
              let comments = get_previous_comment!(
                owner,
                repository,
                pull_request.to_int(),
                token,
                client,
              )
              @io.println(
                "\{owner}#\{repository}#\{pull_request} Fetched comments",
              )
              match comments {
                Some(comment) => {
                  update_comment!(
                    owner, repository, comment, review, token, client,
                  )
                  @io.println(
                    "\{owner}#\{repository}#\{pull_request} Comment updated",
                  )
                }
                None => {
                  create_comment!(
                    owner,
                    repository,
                    pull_request.to_int(),
                    review,
                    token,
                    client,
                  )
                  @io.println(
                    "\{owner}#\{repository}#\{pull_request} Comment posted",
                  )
                }
              }
            } catch {
              _ as error => {
                @io.eprintln("Internal Error: \{error}")
                (body.trailers)() |> ignore
                return internal_error |> Ok
              }
            }
          { "action": String(action), "pull_request": { "url": String(url) } } =>
            "\{action} : \{url}" |> @io.println
          _ => "Unknown json" |> @io.println
        }
      _ => {
        @io.println("Unknown event: \{event}")
        (body.trailers)() |> ignore
        return wrong_request |> Ok
      }
    }
    (body.trailers)() |> ignore
    @http.response() |> Ok
  }
}

fn get_pr_diff(
  owner : String,
  repo : String,
  pull_number : Int64,
  token : String,
  client : @http.HTTPHandler
) -> String!@types.ErrorCode {
  let user_agent = match @variables.get("user_agent") {
    Ok(value) =>
      value.iter()
      |> @utils.encode_utf8
      |> Iter::flat_map(Bytes::iter)
      |> Bytes::from_iter
    Err(e) => {
      @io.eprintln("Error: user_agent not found \{e}")
      raise @types.InternalError(Some("user_agent not found"))
    }
  }
  let request = @http.request(
    Some(github_api),
    path="/repos/\{owner}/\{repo}/pulls/\{pull_number}",
    headers={
      "Accept": [b"application/vnd.github.v3.diff"],
      "Authorization": [
        "token \{token}".iter()
        |> @utils.encode_utf8
        |> Iter::flat_map(Bytes::iter)
        |> Bytes::from_iter,
      ],
      "User-Agent": [user_agent],
    },
  )
  let response = (client._)(request).unwrap_or_error!()
  if response.status != 200 {
    @io.eprintln("Error fetching diff: \{response.status}")
    @io.eprintln("Error Reason: \{response.body.text()}")
    (response.body.trailers)() |> ignore
    raise @types.InternalError(Some("Error fetching diff"))
  } else {
    let text = response.body.text()
    (response.body.trailers)() |> ignore
    text
  }
}

fn get_previous_comment(
  owner : String,
  repo : String,
  issue_number : Int,
  token : String,
  client : @http.HTTPHandler
) -> Int64?!@types.ErrorCode {
  let app_id = match @variables.get("app_id") {
    Ok(value) => value
    Err(e) => {
      @io.eprintln("Error: app_id not found \{e}")
      raise @types.InternalError(Some("app_id not found"))
    }
  }
  let user_agent = match @variables.get("user_agent") {
    Ok(value) =>
      value.iter()
      |> @utils.encode_utf8
      |> Iter::flat_map(Bytes::iter)
      |> Bytes::from_iter
    Err(e) => {
      @io.eprintln("Error: user_agent not found \{e}")
      raise @types.InternalError(Some("user_agent not found"))
    }
  }
  let request = @http.request(
    Some(github_api),
    path="/repos/\{owner}/\{repo}/issues/\{issue_number}/comments",
    headers={
      "Accept": [b"application/vnd.github.v3+json"],
      "Authorization": [
        "token \{token}".iter()
        |> @utils.encode_utf8
        |> Iter::flat_map(Bytes::iter)
        |> Bytes::from_iter,
      ],
      "User-Agent": [user_agent],
    },
  )
  let response = (client._)(request).unwrap_or_error!()
  if response.status != 200 {
    @io.eprintln("Error fetching comment:s \{response.status}")
    @io.eprintln("Error Reason: \{response.body.text()}")
    (response.body.trailers)() |> ignore
    raise @types.InternalError(Some("Error fetching comments"))
  }
  try {
    let json = response.body.json!()
    (response.body.trailers)() |> ignore
    json
  } catch {
    parse_error => {
      @io.eprintln("Error parsing comments: \{parse_error}")
      (response.body.trailers)() |> ignore
      raise @types.InternalError(Some("Error parsing json"))
    }
  } else {
    Array(comments) =>
      comments
      .iter()
      .find_first(
        fn {
          { "performed_via_github_app": { "id": Number(id) } } =>
            id.to_int64().to_string() == app_id
          _ => false
        },
      )
      .map(
        fn {
          { "id": Number(id) } => Some(id.to_int64())
          _ => None
        },
      )
      .flatten()
    _ as json => {
      let json = json.stringify()
      @io.eprintln("Error parsing comments: \{json}")
      raise @types.InternalError(Some("Error parsing json"))
    }
  }
}

fn create_installation_access_token(
  installation : String,
  client : @http.HTTPHandler
) -> String!@types.ErrorCode {
  let jwt = @crypto.jwt()
  let user_agent = match @variables.get("user_agent") {
    Ok(value) =>
      value.iter()
      |> @utils.encode_utf8
      |> Iter::flat_map(Bytes::iter)
      |> Bytes::from_iter
    Err(e) => {
      @io.eprintln("Error: user_agent not found \{e}")
      raise @types.InternalError(Some("user_agent not found"))
    }
  }
  let request = @http.request(
    Some(github_api),
    path="/app/installations/\{installation}/access_tokens",
    method=@types.Post,
    headers={
      "Accept": [b"application/vnd.github.v3+json"],
      "Authorization": [
        "Bearer ".iter() + jwt
        |> @utils.encode_utf8
        |> Iter::flat_map(Bytes::iter)
        |> Bytes::from_iter,
      ],
      "User-Agent": [user_agent],
      "X-Github-Api-Version": [b"2022-11-28"],
    },
  )
  let response = (client._)(request).unwrap_or_error!()
  if response.status != 201 {
    @io.eprintln("Error creating access token: \{response.status}")
    @io.eprintln("Error Reason: \{response.body.text()}")
    (response.body.trailers)() |> ignore
    raise @types.InternalError(Some("Error creating access token"))
  }
  try {
    let json = response.body.json!()
    (response.body.trailers)() |> ignore
    json
  } catch {
    parse_error => {
      @io.eprintln("Error parsing token response: \{parse_error}")
      (response.body.trailers)() |> ignore
      raise @types.InternalError(Some("Error parsing json"))
    }
  } else {
    { "token": String(token) } => token
    json => {
      let json = json.stringify()
      @io.eprintln("Error parsing token response: \{json}")
      raise @types.InternalError(Some("Error parsing json"))
    }
  }
}

fn create_comment(
  owner : String,
  repo : String,
  issue_number : Int,
  body : String,
  token : String,
  client : @http.HTTPHandler
) -> Unit!@types.ErrorCode {
  let user_agent = match @variables.get("user_agent") {
    Ok(value) =>
      value.iter()
      |> @utils.encode_utf8
      |> Iter::flat_map(Bytes::iter)
      |> Bytes::from_iter
    Err(e) => {
      @io.eprintln("Error: user_agent not found \{e}")
      raise @types.InternalError(Some("user_agent not found"))
    }
  }
  let content : Json = { "body": String(body) }
  let request = @http.request(
    Some(github_api),
    path="/repos/\{owner}/\{repo}/issues/\{issue_number}/comments",
    method=@types.Post,
    headers={
      "Accept": [b"application/vnd.github.v3+json"],
      "Authorization": [
        "token \{token}".iter()
        |> @utils.encode_utf8
        |> Iter::flat_map(Bytes::iter)
        |> Bytes::from_iter,
      ],
      "User-Agent": [user_agent],
      "X-Github-Api-Version": [b"2022-11-28"],
    },
    body={
      content: content.stringify().iter() |> @utils.encode_utf8,
      trailers: fn() { Ok({  }) },
    },
  )
  let response = (client._)(request).unwrap_or_error!()
  if response.status != 201 {
    @io.eprintln("Error creating comment: \{response.status}")
    @io.eprintln("Error Reason: \{response.body.text()}")
    (response.body.trailers)() |> ignore
    raise @types.InternalError(Some("Error creating comment"))
  }
  (response.body.trailers)() |> ignore
}

fn update_comment(
  owner : String,
  repo : String,
  comment_id : Int64,
  body : String,
  token : String,
  client : @http.HTTPHandler
) -> Unit!@types.ErrorCode {
  let user_agent = match @variables.get("user_agent") {
    Ok(value) =>
      value.iter()
      |> @utils.encode_utf8
      |> Iter::flat_map(Bytes::iter)
      |> Bytes::from_iter
    Err(e) => {
      @io.eprintln("Error: user_agent not found \{e}")
      raise @types.InternalError(Some("user_agent not found"))
    }
  }
  let content : Json = { "body": String(body) }
  let request = @http.request(
    Some(github_api),
    path="/repos/\{owner}/\{repo}/issues/comments/\{comment_id}",
    method=@types.Patch,
    headers={
      "Accept": [b"application/vnd.github.v3+json"],
      "Authorization": [
        "token \{token}".iter()
        |> @utils.encode_utf8
        |> Iter::flat_map(Bytes::iter)
        |> Bytes::from_iter,
      ],
      "User-Agent": [user_agent],
      "X-Github-Api-Version": [b"2022-11-28"],
    },
    body={
      content: content.stringify().iter() |> @utils.encode_utf8,
      trailers: fn() { Ok({  }) },
    },
  )
  let response = (client._)(request).unwrap_or_error!()
  if response.status != 200 {
    @io.eprintln("Error updating comment: \{response.status}")
    @io.eprintln("Error Reason: \{response.body.text()}")
    (response.body.trailers)() |> ignore
    raise @types.InternalError(Some("Error updating comment"))
  }
  (response.body.trailers)() |> ignore
}

/// Get code review from Deepseek
fn get_code_review_from_deepseek(
  content : String,
  client : @http.HTTPHandler
) -> String!@types.ErrorCode {
  let api_key = match @variables.get("open_api_key") {
    Ok(value) => value
    Err(_) => {
      @io.eprintln("Error: open_api_key not found")
      raise @types.InternalError(Some("open_api_key not found"))
    }
  }
  // "model": "deepseek-coder",
  let content : Json = {
    "model": "deepseek-ai/DeepSeek-Coder-V2-Instruct",
    "messages": [
      {
        "role": "system",
        "content": String(
          #|You are a helpful assistant and an expert in programming. 
          #|The user will provide the output of `git diff`. 
          #|Please provide suggestions on problems that you've discovered, such as potential bugs or typos, etc.
          #|Point out at most three problems that you observe.
          ,
        ),
      },
      { "role": "user", "content": String(content) },
    ],
    "stream": false,
  }
  let request = @http.request(
    // Some("api.deepseek.com"),
    // path="/chat/completions",
    Some("api.siliconflow.cn"),
    path="/v1/chat/completions",
    method=@types.Post,
    scheme=Some(@types.Https),
    headers={
      "Content-Type": [b"application/json"],
      "Authorization": [
        "Bearer \{api_key}".iter()
        |> @utils.encode_utf8
        |> Iter::flat_map(Bytes::iter)
        |> Bytes::from_iter,
      ],
    },
    body={
      content: content.stringify().iter() |> @utils.encode_utf8,
      trailers: fn() { Ok({  }) },
    },
  )
  let response = (client._)(request).unwrap_or_error!()
  if response.status != 200 {
    @io.eprintln("Error fetching comment: \{response.status}")
    @io.eprintln("Error Reason: \{response.body.text()}")
    (response.body.trailers)() |> ignore
    raise @types.InternalError(Some("Error fetching comment"))
  }
  try {
    let json = response.body.json!()
    (response.body.trailers)() |> ignore
    json
  } catch {
    parse_error => {
      @io.eprintln("Error parsing Deepseek response: \{parse_error}")
      (response.body.trailers)() |> ignore
      raise @types.InternalError(Some("Error parsing json"))
    }
  } else {
    { "choices": [{ "message": { "content": String(text) } }], "usage": usage } => {
      @io.println("Usage: \{usage.stringify()}")
      text
    }
    json => {
      let json = json.stringify()
      @io.eprintln("Error parsing Deepseek response: \{json}")
      raise @types.InternalError(Some("Error parsing json"))
    }
  }
}

/// The entrance to the server, which is implemented with a router.
let server : @http.HTTPHandler = Router([Routed("/", @types.Post, handler())])
  |> @http.to_handler
