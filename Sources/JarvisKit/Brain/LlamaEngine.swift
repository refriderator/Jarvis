import Foundation
import llama

/// Runs a GGUF model inside Jarvis with llama.cpp (Metal). The model stays loaded between questions.
public actor LlamaEngine {
    public static let maxNewTokens = 400
    private static let contextSlack = 64

    /// The model is dropped after this long unused, which gives its memory back.
    public static let idleSeconds: Double = 60

    private var loadedPath: String?
    private var model: OpaquePointer?
    private var idleTask: Task<Void, Never>?

    public init() {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }

    /// The model's reply to `messages` (role, text), and how many tokens went in and out.
    public func generate(modelPath: String, messages: [(role: String, text: String)]) throws -> (text: String, input: Int, output: Int) {
        idleTask?.cancel()
        defer { scheduleUnload() }
        let model = try load(modelPath)
        guard let vocab = llama_model_get_vocab(model) else { throw ChatError("Built-in model has no vocabulary.") }

        let prompt = try Self.prompt(model, messages)
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 8)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0 else { throw ChatError("Couldn't read the question.") }
        tokens = Array(tokens.prefix(Int(count)))

        var params = llama_context_default_params()
        params.n_ctx = UInt32(tokens.count + Self.maxNewTokens + Self.contextSlack)
        params.n_batch = UInt32(tokens.count)
        guard let context = llama_init_from_model(model, params) else { throw ChatError("Not enough memory for the built-in model.") }
        defer { llama_free(context) }

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.8, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        // llama_batch_get_one keeps the pointer, so both buffers must outlive the loop.
        let promptBuffer = UnsafeMutablePointer<llama_token>.allocate(capacity: tokens.count)
        promptBuffer.initialize(from: tokens, count: tokens.count)
        let nextBuffer = UnsafeMutablePointer<llama_token>.allocate(capacity: 1)
        defer {
            promptBuffer.deallocate()
            nextBuffer.deallocate()
        }

        var bytes: [UInt8] = []
        var batch = llama_batch_get_one(promptBuffer, Int32(tokens.count))
        var produced = 0
        while produced < Self.maxNewTokens, !Task.isCancelled {
            guard llama_decode(context, batch) == 0 else { throw ChatError("The built-in model stopped unexpectedly.") }
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += Self.piece(vocab, token)
            produced += 1
            nextBuffer.pointee = token
            batch = llama_batch_get_one(nextBuffer, 1)
        }
        return (Self.clean(String(decoding: bytes, as: UTF8.self)), tokens.count, produced)
    }

    /// Frees the model. Also needed before quitting, or ggml's Metal teardown aborts.
    public func unload() {
        idleTask?.cancel()
        if let model { llama_model_free(model) }
        model = nil
        loadedPath = nil
    }

    private func scheduleUnload() {
        idleTask = Task {
            try? await Task.sleep(for: .seconds(Self.idleSeconds))
            if !Task.isCancelled { unload() }
        }
    }

    private func load(_ path: String) throws -> OpaquePointer {
        if let model, loadedPath == path { return model }
        unload()
        var params = llama_model_default_params()
        params.n_gpu_layers = 99
        guard let loaded = llama_model_load_from_file(path, params) else {
            throw ChatError("Couldn't load the built-in model. Try downloading it again in Settings.")
        }
        model = loaded
        loadedPath = path
        return loaded
    }

    /// The model's own chat template applied to the conversation.
    private static func prompt(_ model: OpaquePointer, _ messages: [(role: String, text: String)]) throws -> String {
        let roles = messages.map { strdup($0.role) }
        let texts = messages.map { strdup($0.text) }
        defer { (roles + texts).forEach { free($0) } }
        let chat = zip(roles, texts).map { llama_chat_message(role: UnsafePointer($0), content: UnsafePointer($1)) }
        let template = llama_model_chat_template(model, nil)
        var size = messages.reduce(0) { $0 + $1.text.utf8.count + $1.role.utf8.count } * 2 + 256
        var buffer = [CChar](repeating: 0, count: size)
        var written = llama_chat_apply_template(template, chat, chat.count, true, &buffer, Int32(size))
        if Int(written) > size {
            size = Int(written)
            buffer = [CChar](repeating: 0, count: size)
            written = llama_chat_apply_template(template, chat, chat.count, true, &buffer, Int32(size))
        }
        guard written > 0 else { throw ChatError("The built-in model has no chat format.") }
        return String(decoding: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func piece(_ vocab: OpaquePointer, _ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(max(Int(length), 0)).map { UInt8(bitPattern: $0) }
    }

    /// Qwen3 can think out loud first; only the answer is wanted.
    nonisolated public static func clean(_ text: String) -> String {
        let withoutThinking = text.replacing(/(?s)<think>.*?(<\/think>|$)/, with: "")
        return withoutThinking.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
