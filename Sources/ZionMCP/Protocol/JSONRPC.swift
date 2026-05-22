// JSONRPC.swift — JSON-RPC 2.0 framing for ZionMCP stdio server
// One message per line (newline-delimited JSON).

import Foundation

// MARK: - ID

/// JSON-RPC 2.0 id: int, string, or null.
enum JSONRPCID: Codable, Equatable, Sendable {
    case int(Int)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "id must be int, string, or null")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v):    try container.encode(v)
        case .string(let v): try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }
}

// MARK: - Request

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let method: String
    let id: JSONRPCID?
    let params: JSONValue?
}

// MARK: - Response

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCID?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONRPCID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

// MARK: - Error

struct JSONRPCError: Codable, Sendable, Error {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard error codes
    static let parseError      = JSONRPCError(code: -32700, message: "Parse error")
    static let invalidRequest  = JSONRPCError(code: -32600, message: "Invalid Request")
    static let methodNotFound  = JSONRPCError(code: -32601, message: "Method not found")
    static let invalidParams   = JSONRPCError(code: -32602, message: "Invalid params")
    static let internalError   = JSONRPCError(code: -32603, message: "Internal error")
}

// MARK: - JSONValue (heterogeneous JSON)

indirect enum JSONValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:           try container.encodeNil()
        case .bool(let b):   try container.encode(b)
        case .int(let i):    try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a):  try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - Server

/// Reads JSON-RPC requests from stdin line-by-line, dispatches via registered handlers,
/// writes JSON-RPC responses to stdout.
final class Server: @unchecked Sendable {
    typealias Handler = (JSONRPCRequest) throws -> JSONValue

    private var handlers: [String: Handler] = [:]
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()
    private let decoder = JSONDecoder()

    func register(method: String, handler: @escaping Handler) {
        handlers[method] = handler
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }

            let response: JSONRPCResponse
            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: data)
                guard request.jsonrpc == "2.0" else {
                    response = JSONRPCResponse(id: request.id, error: .invalidRequest)
                    write(response)
                    continue
                }
                if let handler = handlers[request.method] {
                    let result = try handler(request)
                    response = JSONRPCResponse(id: request.id, result: result)
                } else {
                    response = JSONRPCResponse(id: request.id, error: .methodNotFound)
                }
            } catch let decodeError as DecodingError {
                _ = decodeError
                response = JSONRPCResponse(id: nil, error: .parseError)
            } catch {
                response = JSONRPCResponse(id: nil, error: JSONRPCError(code: -32603, message: error.localizedDescription))
            }
            write(response)
        }
    }

    private func write(_ response: JSONRPCResponse) {
        guard let data = try? encoder.encode(response),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
    }
}
