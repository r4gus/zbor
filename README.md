# zbor

> Note: This project is in an early stage and not feature complete.

The Concise Binary Object Representation (CBOR) is a data format whose design 
goals include the possibility of extremely small code size, fairly small 
message size, and extensibility without the need for version negotiation
([RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html#abstract)). It is used
in different protocols like [CTAP](https://fidoalliance.org/specs/fido-v2.0-ps-20190130/fido-client-to-authenticator-protocol-v2.0-ps-20190130.html#ctap2-canonical-cbor-encoding-form) 
and [WebAuthn](https://www.w3.org/TR/webauthn-2/#cbor) (FIDO2).

## Supported types

[ x ] Unsigned integers in the range $$[0, 2^{64}-1]$$ (major type 0).
[ x ] Negative integers in the range $$[-2^{64}, -1]$$ (major type 1).
[ x ] Byte strings (major type 2).
[ x ] Text strings (major type 3).
[ x ] Array of data items (major type 4).
[ x ] Map of pairs of data items (major type 5).
[ ] Tagged data item whose tag number is in the range $$[0, 2^{64}-1]$$ (major type 6).
[ ] Floating-point numbers and simple values, as well as the "break" stop code (major type 7).

## Project Status

| Task | Todo | In progress | Done |
|:----:|:----:|:-----------:|:----:|
| Decoder | | x | |
| Encoder | x | | |
| CBOR to JSON | x | | |
| JSON to CBOR | x | | |
