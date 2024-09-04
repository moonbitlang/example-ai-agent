pub fn wasmExportHandle(p0 : Int, p1 : Int) -> Unit {
  server.serve()(
    @types.IncomingRequest::IncomingRequest(p0),
    @types.ResponseOutparam::ResponseOutparam(p1),
  )
}

let server : @http.HTTPHandler = panic()
