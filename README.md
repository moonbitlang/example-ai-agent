# MoonBit AI Agent using Components

## Requirements

The following tools are needed:

- [spin cli](https://developer.fermyon.com/spin/v2/install) and a fermyon cloud account if you'd like to deploy it at the end
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools)

and of course, [moonbit toolchain](https://www.moonbitlang.com/download/).

For this example, you will also need to [create a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) and obtain the private key, the client ID and the App ID and the secret. You may consider following the step 2 through 5 with [the official tutorial](https://docs.github.com/en/apps/creating-github-apps/writing-code-for-a-github-app/quickstart). You may configure the callback URL of the GitHub App with the Spin application for production or a proxy (e.g. <smee.io>) for local development.

You also need to have access to an AI provider, such as [DeepSeek](https://www.deepseek.com/) or [Silicon Flow](https://siliconflow.cn/models). You need an API Key to access the LLM, the endpoint the the completion functionality, and the name of the LLM that you'd like to use. We are using the DeepSeek Coder provided by Silicon Flow in this demo.

## How to use

- Copy the folder `gen` to the one you like, and then implement the `let server` global variable.
- Add configurations in `spin.toml` as the existing one.

Build commands:
- Install dependency with `moon update && moon install`
- Local development: `spin build && spin up`.
- Publish: `./publish.sh`. Don't forget to `spin login` the service.

### Environment variables

Copy `.env.template` to `.env` and fill in the environment variables.

They are configured in `variables` for `spin.toml` and `component.agent.variables` will use them so that component can have access. The example application use the environment variables to pass secrets. One may use external vault in production. Check out the [official document](https://developer.fermyon.com/spin/v2/variables).

## Project Structure

Most files are generated with

```bash
wit-bindgen moonbit --derive-show --derive-eq --derive-error --out-dir . wit
```

Note that the MoonBit support is accepted by the `bytecode-alliance/wit-bindgen` so there is where you should install the `wit-bindgen`now.

Apart from the auto-generated code:

- `agent`: an example of AI Agent using MoonBit.

- `http`: a wrapper around the underlying `wasi-http` interface, providing proper lifetime handling. One should always call `response.body.trailer` before it goes out of scope. It is built with the concept of ["Your Server as a Function"](https://monkey.org/~marius/funsrv.pdf) as [http4k](https://www.http4k.org) as well as the `wasi-http` itself.
  
- `crypto`: containing a jwt RS256 implementation for signing GitHub access token, and necessary RSA / HMAC algorithms.
  
- `io`: a thin wrapper around the underlying `wasi-io` streams.
  
- `utils`: some helper functions for encoding/decoding base64 and utf-8.

## Future Work

As of the project itself, there are several things we can improve:

- We should validate incoming deliveries with the HMAC algorithms (which is implemented)
- Use Vault for keys
- Use Redis Trigger for long running task (though not yet supported by fermyon cloud)