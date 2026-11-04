// The languages Whisper can be told to transcribe, as the speech-recognition
// library knows them: its WHISPER_LANGUAGES and the other names it accepts
// (@huggingface/transformers 4.3.2, models/whisper/common_whisper.js). Copied
// rather than imported because the page doesn't load the library — only the
// recognition Worker does — and this list is all the page needs of it.
//
// The library can't detect a language: given a multilingual model and none,
// it transcribes as English. So a run has to be told.

// [ code, name ], in the library's order (roughly by how much training data).
export const WHISPER_LANGUAGES = Object.freeze([
    [ 'en', 'english' ],
    [ 'zh', 'chinese' ],
    [ 'de', 'german' ],
    [ 'es', 'spanish' ],
    [ 'ru', 'russian' ],
    [ 'ko', 'korean' ],
    [ 'fr', 'french' ],
    [ 'ja', 'japanese' ],
    [ 'pt', 'portuguese' ],
    [ 'tr', 'turkish' ],
    [ 'pl', 'polish' ],
    [ 'ca', 'catalan' ],
    [ 'nl', 'dutch' ],
    [ 'ar', 'arabic' ],
    [ 'sv', 'swedish' ],
    [ 'it', 'italian' ],
    [ 'id', 'indonesian' ],
    [ 'hi', 'hindi' ],
    [ 'fi', 'finnish' ],
    [ 'vi', 'vietnamese' ],
    [ 'he', 'hebrew' ],
    [ 'uk', 'ukrainian' ],
    [ 'el', 'greek' ],
    [ 'ms', 'malay' ],
    [ 'cs', 'czech' ],
    [ 'ro', 'romanian' ],
    [ 'da', 'danish' ],
    [ 'hu', 'hungarian' ],
    [ 'ta', 'tamil' ],
    [ 'no', 'norwegian' ],
    [ 'th', 'thai' ],
    [ 'ur', 'urdu' ],
    [ 'hr', 'croatian' ],
    [ 'bg', 'bulgarian' ],
    [ 'lt', 'lithuanian' ],
    [ 'la', 'latin' ],
    [ 'mi', 'maori' ],
    [ 'ml', 'malayalam' ],
    [ 'cy', 'welsh' ],
    [ 'sk', 'slovak' ],
    [ 'te', 'telugu' ],
    [ 'fa', 'persian' ],
    [ 'lv', 'latvian' ],
    [ 'bn', 'bengali' ],
    [ 'sr', 'serbian' ],
    [ 'az', 'azerbaijani' ],
    [ 'sl', 'slovenian' ],
    [ 'kn', 'kannada' ],
    [ 'et', 'estonian' ],
    [ 'mk', 'macedonian' ],
    [ 'br', 'breton' ],
    [ 'eu', 'basque' ],
    [ 'is', 'icelandic' ],
    [ 'hy', 'armenian' ],
    [ 'ne', 'nepali' ],
    [ 'mn', 'mongolian' ],
    [ 'bs', 'bosnian' ],
    [ 'kk', 'kazakh' ],
    [ 'sq', 'albanian' ],
    [ 'sw', 'swahili' ],
    [ 'gl', 'galician' ],
    [ 'mr', 'marathi' ],
    [ 'pa', 'punjabi' ],
    [ 'si', 'sinhala' ],
    [ 'km', 'khmer' ],
    [ 'sn', 'shona' ],
    [ 'yo', 'yoruba' ],
    [ 'so', 'somali' ],
    [ 'af', 'afrikaans' ],
    [ 'oc', 'occitan' ],
    [ 'ka', 'georgian' ],
    [ 'be', 'belarusian' ],
    [ 'tg', 'tajik' ],
    [ 'sd', 'sindhi' ],
    [ 'gu', 'gujarati' ],
    [ 'am', 'amharic' ],
    [ 'yi', 'yiddish' ],
    [ 'lo', 'lao' ],
    [ 'uz', 'uzbek' ],
    [ 'fo', 'faroese' ],
    [ 'ht', 'haitian creole' ],
    [ 'ps', 'pashto' ],
    [ 'tk', 'turkmen' ],
    [ 'nn', 'nynorsk' ],
    [ 'mt', 'maltese' ],
    [ 'sa', 'sanskrit' ],
    [ 'lb', 'luxembourgish' ],
    [ 'my', 'myanmar' ],
    [ 'bo', 'tibetan' ],
    [ 'tl', 'tagalog' ],
    [ 'mg', 'malagasy' ],
    [ 'as', 'assamese' ],
    [ 'tt', 'tatar' ],
    [ 'haw', 'hawaiian' ],
    [ 'ln', 'lingala' ],
    [ 'ha', 'hausa' ],
    [ 'ba', 'bashkir' ],
    [ 'jw', 'javanese' ],
    [ 'su', 'sundanese' ]
]);

// Other names the library accepts for a language: [ name, code ].
const ALIASES = [
    [ 'burmese', 'my' ],
    [ 'valencian', 'ca' ],
    [ 'flemish', 'nl' ],
    [ 'haitian', 'ht' ],
    [ 'letzeburgesch', 'lb' ],
    [ 'pushto', 'ps' ],
    [ 'panjabi', 'pa' ],
    [ 'moldavian', 'ro' ],
    [ 'moldovan', 'ro' ],
    [ 'sinhalese', 'si' ],
    [ 'castilian', 'es' ]
];

const BY_CODE = new Map(WHISPER_LANGUAGES);
const BY_NAME = new Map([ ...WHISPER_LANGUAGES.map(([ c, n ]) => [ n, c ]), ...ALIASES ]);

// A code from what someone typed — a name (any case), an alias, or a code —
// or null if Whisper doesn't know it.
export function language_code(input){
    const s = String(input ?? '').trim().toLowerCase();
    if(BY_CODE.has(s)) return s;
    return BY_NAME.get(s) ?? null;
}

// "French" for fr.
export function language_name(code){
    const n = BY_CODE.get(code);
    return n ? n.replace(/(^|\s)\S/g, (c) => c.toUpperCase()) : code;
}
