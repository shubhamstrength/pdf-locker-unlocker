# Vendored files

`qpdf.js` and `qpdf.wasm` come unmodified from the npm package
[`@neslinesli93/qpdf-wasm@0.3.0`](https://www.npmjs.com/package/@neslinesli93/qpdf-wasm)
(ISC license, source at https://github.com/neslinesli93/qpdf-wasm), which compiles
[qpdf](https://github.com/qpdf/qpdf) (Apache License 2.0) to WebAssembly with Emscripten.

To update them:

```sh
npm pack @neslinesli93/qpdf-wasm@<version>
tar xzf neslinesli93-qpdf-wasm-<version>.tgz
cp package/dist/qpdf.js package/dist/qpdf.wasm web/vendor/
```
