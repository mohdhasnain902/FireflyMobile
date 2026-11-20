# Open-source notices — Firefly III Mobile

This application bundles the following third-party components. This file is
referenced by the in-app **Settings → About → Open-source licenses** screen
and must stay user-accessible in every distributed build.

Licensing verdict (verified 2026-10-15): **SQLCipher Community Edition is
BSD-3-Clause** — free for closed-source commercial use subject to the
attribution reproduced below. The Commercial Edition (paid) is NOT required
for this app. Source: https://www.zetetic.net/sqlcipher/license/ and
github.com/sqlcipher/sqlcipher `LICENSE.md`.

---

## SQLCipher (Community Edition)

Bundled as `libsqlcipher.so` for android-arm64 / armeabi-v7a / x86_64, built
from source by the `sqlite3` package hook
(`hooks.user_defines.sqlite3.source: sqlcipher` in `pubspec.yaml`).

Copyright (c) 2025, ZETETIC LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the ZETETIC LLC nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY ZETETIC LLC ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL ZETETIC LLC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

## SQLite

The SQLite source code incorporated by SQLCipher is in the public domain.
See https://www.sqlite.org/copyright.html.

---

## OpenSSL 3.6.3

OpenSSL 3.6.3 (9 Jun 2026) is **statically linked** into the bundled
`libsqlcipher.so` (verified: no dynamic `libcrypto`/`libssl` NEEDED entry;
version string present in the binary).

Copyright The OpenSSL Project Authors

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy
of the License at https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

OpenSSL is distributed with an OPTIONAL attribution: "This product includes
software developed by the OpenSSL Project for use in the OpenSSL Toolkit
(https://www.openssl.org/)."
