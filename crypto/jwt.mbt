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

pub fn jwt() -> Iter[Char] {
  // Get information
  let private_key = @variables.get("private_key").unwrap()
  let client_id = @variables.get("client_id").unwrap()
  let { seconds: now, .. } = @wallClock.now()
  let issue_time = now - 60 // 60 seconds in the past as per GitHub suggestion
  let expire_time = now + 600 // no more than 10 minutes as per GitHub requirement
  // Prepare signature
  let [sequence] = private_key
    .split("\n")
    .drop(1)
    .take_while(fn(str) { str.starts_with("----END").not() })
    .flat_map(String::iter)
    |> @utils.base64_decode
    |> from_iter
    |> Iter::collect
  let [
    _version,
    modulus,
    _public_exponent,
    _private_exponent,
    prime1,
    prime2,
    exponent1,
    exponent2,
    coefficient,
  ] = sequence.content.iter()
    |> from_iter
    |> Iter::map(
      fn {
        { tag: Integer, construction: Primitive, class: Universal, content } =>
          BigInt::from_octets(content)
        _ => panic()
      },
    )
    |> Iter::collect
  let metadata = ({ "alg": "RS256", "typ": "JWT" } : Json)
    |> @json.stringify
    |> String::iter
    |> @utils.encode_utf8
    |> @utils.base64_encode(url_safe=true)
    |> Iter::filter(fn(ch) { ch != '=' }) // omit as per rfc7515 section 2
  let payload = "{\"iat\":\{issue_time.to_string()}, \"exp\":\{expire_time.to_string()}, \"iss\":\"\{client_id}\"}".iter()
    |> @utils.encode_utf8
    |> @utils.base64_encode(url_safe=true)
    |> Iter::filter(fn(ch) { ch != '=' }) // omit as per rfc7515 section 2
  let signature = metadata + ".".iter() + payload
    |> @utils.encode_utf8
    |> Iter::flat_map(Bytes::iter)
    // |> rsassa_pkcs1_v1_5_sign(Pair(~modulus, exponent=private_exponent)) // using other format is faster
    |> rsassa_pkcs1_v1_5_sign(
      Quintuple(
        factor1=prime1,
        factor2=prime2,
        ~exponent1,
        ~exponent2,
        ~coefficient,
        triplets=[],
        length=modulus.to_octets().length() * 8,
      ),
    )
  let signature = [signature.to_octets()].iter()
    |> @utils.base64_encode(url_safe=true)
    |> Iter::filter(fn(ch) { ch != '=' }) // omit as per rfc7515 section 2
  metadata + ".".iter() + payload + ".".iter() + signature
}
