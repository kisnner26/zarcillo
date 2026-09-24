import CryptoKit
import Foundation
import Network

extension NWParameters {
    /// TCP + TLS con clave precompartida derivada del código de 6 dígitos que
    /// muestra el Mac.
    ///
    /// Sin esto, cualquiera en la misma Wi-Fi podría mover el puntero o teclear
    /// en el Mac. Con PSK, quien no conoce el código ni siquiera completa el
    /// saludo TLS, y todo lo que viaja va cifrado.
    static func zarcillo(passcode: String) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        // El puntero manda paquetes chicos y seguidos: Nagle los agruparía y el
        // cursor iría a saltos.
        tcp.noDelay = true

        let tls = NWProtocolTLS.Options()
        let identity = Data("zarcillo".utf8)
        let key = SymmetricKey(data: Data(passcode.utf8))
        let psk = HMAC<SHA256>.authenticationCode(for: identity, using: key)
        let pskData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let idData = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        let sec = tls.securityProtocolOptions
        sec_protocol_options_add_pre_shared_key(sec, pskData as __DispatchData, idData as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(
            sec, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        // Las suites PSK de Network.framework son de TLS 1.2.
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
        // Sin reanudación: una sesión guardada de antes permitiría entrar sin
        // el código actual, incluso después de generar uno nuevo en el Mac.
        sec_protocol_options_set_tls_resumption_enabled(sec, false)

        let params = NWParameters(tls: tls, tcp: tcp)
        params.includePeerToPeer = true
        return params
    }
}

/// Una conexión con mensajes enmarcados: 4 bytes de largo (big endian) + JSON.
final class Channel {
    let connection: NWConnection
    var onData: ((Data) -> Void)?
    var onState: ((NWConnection.State) -> Void)?
    private let queue = DispatchQueue(label: "zarcillo.channel")

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in self?.onState?(state) }
        connection.start(queue: queue)
        readHeader()
    }

    func cancel() {
        connection.cancel()
    }

    func send<T: Encodable>(_ value: T) {
        guard let body = try? JSONEncoder().encode(value) else { return }
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func readHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, data.count == 4 else { self.connection.cancel(); return }
            let length = data.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            // Tope generoso: la lista de apps con iconos es lo más pesado que viaja.
            guard length > 0, length < 32_000_000 else { self.connection.cancel(); return }
            self.readBody(Int(length))
        }
    }

    private func readBody(_ length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, data.count == length else { self.connection.cancel(); return }
            self.onData?(data)
            self.readHeader()
        }
    }
}
