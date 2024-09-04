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

pub fn decode_utf8(bytes : Iter[Byte]) -> Iter[Char] {
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

pub fn iter_to_string(iter : Iter[Char]) -> String {
  let buffer = Buffer::new()
  iter.each(fn(ch) { buffer.write_char(ch) })
  buffer.to_string()
}

pub fn encode_utf8(string : Iter[Char]) -> Iter[Bytes] {
  Iter::new(
    fn(f) {
      for char in string {
        let point = char.to_int()
        if point < 0x80 {
          let bytes = Bytes::new(1)
          bytes[0] = (((point >> 0) & 0x7F) | 0x00).to_byte()
          match f(bytes) {
            IterEnd => break IterEnd
            _ => continue
          }
        } else if point < 0x0800 {
          let bytes = Bytes::new(2)
          bytes[0] = (((point >> 6) & 0x1F) | 0xC0).to_byte()
          bytes[1] = (((point >> 0) & 0x3F) | 0x80).to_byte()
          match f(bytes) {
            IterEnd => break IterEnd
            _ => continue
          }
        } else if point < 0x10000 {
          let bytes = Bytes::new(3)
          bytes[0] = (((point >> 12) & 0x0F) | 0xE0).to_byte()
          bytes[1] = (((point >> 6) & 0x3F) | 0x80).to_byte()
          bytes[2] = (((point >> 0) & 0x3F) | 0x80).to_byte()
          match f(bytes) {
            IterEnd => break IterEnd
            _ => continue
          }
        } else if point < 0x110000 {
          let bytes = Bytes::new(4)
          bytes[0] = (((point >> 18) & 0x07) | 0xF0).to_byte()
          bytes[1] = (((point >> 12) & 0x3F) | 0x80).to_byte()
          bytes[2] = (((point >> 6) & 0x3F) | 0x80).to_byte()
          bytes[3] = (((point >> 0) & 0x3F) | 0x80).to_byte()
          match f(bytes) {
            IterEnd => break IterEnd
            _ => continue
          }
        }
      } else {
        IterContinue
      }
    },
  )
}
