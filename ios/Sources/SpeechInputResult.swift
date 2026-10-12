/// The native recognizer replaces an utterance's partial text until it becomes final.
struct SpeechInputResult: Sendable { let text: String; let isFinal: Bool }
