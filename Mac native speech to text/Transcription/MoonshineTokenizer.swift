//
//  MoonshineTokenizer.swift
//  Mac native speech to text
//
//  Minimal token-id → text decoder for Moonshine. We only need the
//  decoding direction (model emits ids, we display text) so this is much
//  smaller than a full BPE encoder. The tokenizer.json file shipped with
//  Moonshine is the standard Hugging Face tokenizers serialization format;
//  we read just the fields we need.
//

import Foundation

struct MoonshineTokenizer {
    private let idToToken: [Int: String]
    private let specialTokenIDs: Set<Int>
    let bosTokenID: Int
    let eosTokenID: Int
    let padTokenID: Int

    init(tokenizerJSON url: URL) throws {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else {
            throw TranscriptionProviderError.inferenceFailed("tokenizer.json is not a JSON object")
        }

        var idToToken: [Int: String] = [:]
        var specials: Set<Int> = []

        // Vocab can live in either `model.vocab` (BPE/Unigram) or top-level
        // depending on the tokenizer flavor. We probe both.
        if let model = root["model"] as? [String: Any] {
            if let vocab = model["vocab"] as? [String: Int] {
                // BPE/WordPiece: { "token": id, ... }
                for (tok, id) in vocab { idToToken[id] = tok }
            } else if let vocabArr = model["vocab"] as? [[Any]] {
                // Unigram: [[token, score], ...] indexed by position.
                for (id, pair) in vocabArr.enumerated() {
                    if let tok = pair.first as? String {
                        idToToken[id] = tok
                    }
                }
            }
        }

        // Pull special-token ids from added_tokens so we can skip them on
        // decode (e.g. <s>, </s>, <pad>).
        if let added = root["added_tokens"] as? [[String: Any]] {
            for entry in added {
                if let id = entry["id"] as? Int, let content = entry["content"] as? String {
                    idToToken[id] = content
                    if entry["special"] as? Bool == true {
                        specials.insert(id)
                    }
                }
            }
        }

        // Resolve special token ids by canonical name where possible. Fall
        // back to Moonshine defaults (1 = <s>, 2 = </s>, 0 = <pad>).
        func lookupSpecial(_ candidates: [String], default fallback: Int) -> Int {
            for (id, tok) in idToToken where candidates.contains(tok) { return id }
            return fallback
        }
        self.bosTokenID = lookupSpecial(["<s>", "<|startoftranscript|>"], default: 1)
        self.eosTokenID = lookupSpecial(["</s>", "<|endoftext|>"], default: 2)
        self.padTokenID = lookupSpecial(["<pad>", "<|pad|>"], default: 0)

        specials.insert(bosTokenID)
        specials.insert(eosTokenID)
        specials.insert(padTokenID)

        self.idToToken = idToToken
        self.specialTokenIDs = specials

        if idToToken.isEmpty {
            throw TranscriptionProviderError.inferenceFailed("tokenizer.json contained no vocabulary")
        }
    }

    /// Decode an array of token ids into the user-facing string.
    func decode(_ ids: [Int]) -> String {
        var pieces: [String] = []
        pieces.reserveCapacity(ids.count)
        for id in ids {
            if specialTokenIDs.contains(id) { continue }
            guard let token = idToToken[id] else { continue }
            pieces.append(token)
        }
        // SentencePiece uses U+2581 ("▁") as a word boundary marker. Convert
        // to ASCII spaces and strip the leading boundary, matching the
        // reference Moonshine Python decoder.
        let joined = pieces.joined()
        let withSpaces = joined.replacingOccurrences(of: "\u{2581}", with: " ")
        return withSpaces.trimmingCharacters(in: .whitespaces)
    }
}
