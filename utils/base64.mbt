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

fn index_to_char(index : Int, url_safe : Bool) -> Char {
  if index < 26 {
    Char::from_int(index + 65)
  } else if index < 52 {
    Char::from_int(index - 26 + 97)
  } else if index < 62 {
    Char::from_int(index - 52 + 48)
  } else if index == 62 {
    if url_safe {
      '-'
    } else {
      '+'
    }
  } else if url_safe {
    '_'
  } else {
    '/'
  }
}

fn char_to_index(char : Char, url_safe : Bool) -> Int {
  let code = char.to_int()
  if code >= 65 && code <= 90 {
    code - 65
  } else if code >= 97 && code <= 122 {
    code - 97 + 26
  } else if code >= 48 && code <= 57 {
    code - 48 + 52
  } else if url_safe {
    if code == 45 {
      62
    } else {
      63
    }
  } else if code == 43 {
    62
  } else {
    63
  }
}

/// Encode binary to ascii text following Base64 defined in RFC 4648
pub fn base64_encode(
  bytes : Iter[Bytes],
  ~url_safe : Bool = false
) -> Iter[Char] {
  Iter::new(
    fn(f) {
      let mut i = 0
      let mut buffer = 0
      for byte in bytes.flat_map(Bytes::iter) {
        match i % 3 {
          0 => {
            if (index_to_char(byte.lsr(2).to_int(), url_safe) |> f) == IterEnd {
              return IterEnd
            }
            buffer = byte.to_int().land(0b11).lsl(4)
          }
          1 => {
            if (index_to_char(buffer.lor(byte.to_int().lsr(4)), url_safe) |> f) ==
              IterEnd {
              return IterEnd
            }
            buffer = byte.to_int().land(0b1111).lsl(2)
          }
          2 => {
            if (index_to_char(buffer.lor(byte.to_int().lsr(6)), url_safe) |> f) ==
              IterEnd {
              return IterEnd
            }
            if (index_to_char(byte.to_int().land(0b111111), url_safe) |> f) ==
              IterEnd {
              return IterEnd
            }
            buffer = 0
          }
          _ => panic()
        }
        i += 1
        i %= 3
      } else {
        match i % 3 {
          0 => ()
          1 => {
            if (index_to_char(buffer, url_safe) |> f) == IterEnd {
              return IterEnd
            }
            if f('=') == IterEnd {
              return IterEnd
            }
            if f('=') == IterEnd {
              return IterEnd
            }
          }
          2 => {
            if (index_to_char(buffer, url_safe) |> f) == IterEnd {
              return IterEnd
            }
            if f('=') == IterEnd {
              return IterEnd
            }
          }
          _ => panic()
        }
        IterContinue
      }
    },
  )
}

test "base64 encode" {
  fn test_str!(input : String, expected : String) {
    let result = Buffer::new()
    input.iter()
    |> encode_utf8
    |> base64_encode
    |> Iter::each(fn(ch) { result.write_char(ch) })
    inspect!(result, content=expected)
  }

  test_str!("light w", "bGlnaHQgdw==")
  test_str!("light wo", "bGlnaHQgd28=")
  test_str!("light wor", "bGlnaHQgd29y")
  test_str!("light work", "bGlnaHQgd29yaw==")
  test_str!("light work.", "bGlnaHQgd29yay4=")
  test_str!("a Ā 𐀀 文 🦄", "YSDEgCDwkICAIOaWhyDwn6aE")
}

/// Decode ascii text to binary following Base64 defined in RFC 4648
///
/// If the string is not padded correctly, an empty `Bytes` will be returned
pub fn base64_decode(
  input : Iter[Char],
  ~url_safe : Bool = false
) -> Iter[Byte] {
  Iter::new(
    fn(f) {
      let mut i = 0
      let mut buffer = 0
      for ch in input {
        match i % 4 {
          0 => buffer = char_to_index(ch, url_safe).lsl(2)
          1 => {
            let idx = char_to_index(ch, url_safe)
            match f(buffer.lor(idx.lsr(4)).to_byte()) {
              IterEnd => break IterEnd
              IterContinue => ()
            }
            buffer = idx.land(0b1111).lsl(4)
          }
          2 =>
            if ch == '=' {
              break IterContinue
            } else {
              let idx = char_to_index(ch, url_safe)
              match f(buffer.lor(idx.lsr(2)).to_byte()) {
                IterEnd => break IterEnd
                IterContinue => ()
              }
              buffer = idx.land(0b11).lsl(6)
            }
          3 =>
            if ch == '=' {
              break IterContinue
            } else {
              let idx = char_to_index(ch, url_safe)
              match f(buffer.lor(idx).to_byte()) {
                IterEnd => break IterEnd
                IterContinue => ()
              }
            }
          _ => panic()
        }
        i += 1
        i %= 4
      } else {
        IterContinue
      }
    },
  )
}

test "base64 decode" {
  fn test_str!(expected : String, input : String) {
    let result = Buffer::new()
    input.iter()
    |> base64_decode
    |> decode_utf8
    |> Iter::each(fn(ch) { result.write_char(ch) })
    inspect!(result, content=expected)
  }

  test_str!("light w", "bGlnaHQgdw==")
  test_str!("light wo", "bGlnaHQgd28=")
  test_str!("light wor", "bGlnaHQgd29y")
  test_str!("light work", "bGlnaHQgd29yaw==")
  test_str!("light work.", "bGlnaHQgd29yay4=")
  test_str!("a Ā 𐀀 文 🦄", "YSDEgCDwkICAIOaWhyDwn6aE")
}
