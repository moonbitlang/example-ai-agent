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

pub let stdin : @streams.InputStream = @stdin.get_stdin()

pub let stdout : @streams.OutputStream = @stdout.get_stdout()

pub let stderr : @streams.OutputStream = @stderr.get_stderr()

pub fn read(stream : @streams.InputStream) -> Iter[Bytes] {
  Iter::new(
    fn(f) {
      loop stream.blocking_read(4096) {
        Ok(bytes) =>
          match f(bytes) {
            IterEnd => return IterEnd
            IterContinue => continue stream.blocking_read(4096)
          }
        Err(Closed) => return IterContinue
        Err(_) => return IterEnd
      }
    },
  )
}

let output_buffer : Bytes = Bytes::new(4096)

pub fn write(bytes : Iter[Bytes], stream : @streams.OutputStream) -> Unit {
  let mut ptr = 0
  for byte in bytes {
    ptr = loop ptr, byte.length() {
      ptr, 0 => ptr
      ptr, len =>
        if ptr + len <= 4096 {
          output_buffer.blit(ptr, byte, 0, len)
          continue ptr + len, 0
        } else {
          let p = 4096 - ptr
          output_buffer.blit(ptr, byte, 0, p)
          stream.blocking_write_and_flush(output_buffer) |> ignore
          continue 0, len - p
        }
    }
    if ptr == 4096 {
      stream.blocking_write_and_flush(output_buffer) |> ignore
      ptr = 0
    }
  } else {
    let b = Bytes::new(ptr)
    b.blit(0, output_buffer, 0, ptr)
    stream.blocking_write_and_flush(b) |> ignore
  }
}

pub fn writeln(bytes : Iter[Bytes], stream : @streams.OutputStream) -> Unit {
  write(bytes, stream)
  stream.blocking_write_and_flush(b"\n") |> ignore
}

pub fn print(string : String, ~stream : @streams.OutputStream = stdout) -> Unit {
  string.iter() |> @utils.encode_utf8 |> write(stream)
}

pub fn println(
  string : String,
  ~stream : @streams.OutputStream = stdout
) -> Unit {
  string.iter() |> @utils.encode_utf8 |> writeln(stream)
}

pub fn eprint(string : String) -> Unit {
  print(string, stream=stderr)
}

pub fn eprintln(string : String) -> Unit {
  println(string, stream=stderr)
}
