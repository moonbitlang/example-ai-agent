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

pub enum HashAlgorithm {
  MD5
  SHA224
  SHA256
}

pub fn oid(self : HashAlgorithm) -> Array[Int] {
  match self {
    MD5 => [1, 2, 840, 113549, 2, 5]
    SHA224 => [2, 16, 840, 1, 101, 3, 4, 2, 4]
    SHA256 => [2, 16, 840, 1, 101, 3, 4, 2, 1]
  }
}

pub fn oid_with_rsa_encryption(self : HashAlgorithm) -> Array[Int] {
  let pkcs_1 = [1, 2, 840, 113549, 1, 1]
  match self {
    MD5 => [..pkcs_1, 4]
    SHA224 => [..pkcs_1, 14]
    SHA256 => [..pkcs_1, 11]
  }
}

pub fn hash(self : HashAlgorithm, input : Iter[Byte]) -> Bytes {
  match self {
    MD5 => @crypto.md5(Bytes::from_iter(input))
    SHA224 => @crypto.sha224_from_iter(input)
    SHA256 => @crypto.sha256_from_iter(input)
  }
}

pub fn pkcs1_v1_5_digest_algorithms(self : HashAlgorithm) -> X690 {
  {
    tag: Sequence,
    class: Universal,
    construction: Constructed,
    content: {
      let buffer = Buffer::new()
      buffer.write_bytes(
        {
          tag: ObjectIdentifier,
          construction: Primitive,
          class: Universal,
          content: self.oid() |> oid_to_bytes,
        }.to_bytes(),
      )
      buffer.write_bytes(
        { tag: Null, construction: Primitive, class: Universal, content: b"" }.to_bytes(),
      )
      buffer.to_bytes()
    },
  }
}
