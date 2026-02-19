# Interesting Values Dictionary

## Contents
- [Context-Aware Value Generation](#context-aware-value-generation) — generate values based on field type
- [Boundary Numbers](#boundary-numbers-as-strings) — integer/float edge cases
- [Empty and Whitespace](#empty-and-whitespace) — blank and invisible inputs
- [Special Characters](#special-characters) — punctuation and symbol edge cases
- [Injection Strings](#injection-strings) — XSS, SQL, format string payloads
- [Unicode Edge Cases](#unicode-edge-cases) — RTL, CJK, combining marks, emoji
- [Long Strings](#long-strings) — length stress tests
- [Format Strings](#format-strings) — printf-style format specifiers
- [iOS-Specific](#ios-specific) — URL schemes and deep links
- [Null and Control Characters](#null-and-control-characters) — non-printable bytes
- [Realistic Messy Input](#realistic-messy-input) — pasted content and clipboard artifacts
- [Temporal Values](#temporal-values) — boundary dates and malformed timestamps
- [Structured Data in Plain Fields](#structured-data-in-plain-fields) — JSON, XML, SQL in plain text

---

Curated text inputs for `type_text` testing, plus guidance on generating novel values for each session.

## Context-Aware Value Generation

**Before picking from the lists below, read the field.** Look at its label, placeholder, identifier, and keyboard type. Generate values that are *adversarial versions of valid input* for that specific field — not generic injection strings.

### By Field Type

**Name / person fields** — break naming assumptions:
- `O'Brien-Smith Jr.` (apostrophe + hyphen + suffix)
- `Null` / `None` / `True` / `undefined` (programming keywords as real names)
- `María José García-López` (accented + compound + hyphenated)
- `X Æ A-12` (mixed scripts + numbers)
- `信田恵子` (CJK — 4 characters)
- `Мария` (Cyrillic)
- Single character: `M`
- Just a space: ` `
- 200-character realistic name: `Christopher Alexander Montgomery-Worthington the Third...`

**Email fields** — technically-valid-but-weird:
- `a@b.c` (minimal valid)
- `user+fuzztag@example.com` (plus addressing)
- `user@192.168.1.1` (IP as domain)
- `"quoted spaces"@example.com` (quoted local part)
- `user@localhost` (no TLD)
- `user@[IPv6:::1]` (IPv6 literal)
- Very long local part: `aaaa...64chars...@example.com`
- Multiple @ signs: `user@@example.com`

**Phone fields** — format diversity:
- `+1 (555) 123-4567` (US formatted)
- `5551234567` (unformatted)
- `+44 20 7946 0958` (international)
- `000-000-0000` (all zeros)
- `#*1234` (special chars)
- `ext. 5555` (extension text)
- `+999 123456789012345` (too many digits)

**Password fields** — strength extremes:
- Single char: `x`
- Passphrase: `correct horse battery staple`
- 500 characters of mixed content
- Password that matches the email/username value you just typed
- All spaces: `          `
- All special chars: `!@#$%^&*()`

**Amount / price / number fields** — numeric edge cases:
- `0.001` (tiny)
- `$1,000.00` (formatted with currency symbol)
- `1,234.56` vs `1.234,56` (locale-dependent separators)
- `1.999999999999` (precision)
- `-5` (negative in an unsigned context)
- `1e10` (scientific notation)
- `∞` (literal infinity symbol)

**Bio / description / multi-line fields** — content extremes:
- Single word: `Hello`
- 10 paragraphs of text
- Only emoji: `🔥🌊🌎💀👻🤖`
- Only whitespace/newlines
- URL-heavy text: `Check out https://example.com and https://test.org and ...`
- Markdown: `# Heading\n**bold** _italic_ [link](url)`

### Value Mutation

Don't just use listed values verbatim. Mutate them:
- **Truncate**: Take a long value and cut it mid-character (break a UTF-8 multi-byte sequence)
- **Duplicate**: Paste the same value twice: `AliceAlice`
- **Interleave categories**: `0<script>NaN`, a boundary number inside an injection string
- **Contextualize**: Use the app's own labels as test input (type a button's label into a text field)
- **Combine**: `2147483647@example.com` (boundary number as email local part)
- **Vary from listed**: Listed value is `0` → also try `-0.0`, `00`, `0x0`, `0e0`, `0️⃣`

### Randomize, Don't Repeat

- **Start from a random category** each session, not always from the top
- **Generate at least 1 novel value per field** that isn't from any list below
- **Never type "Alice" session after session** — pick a different realistic name each time

---

## Boundary Numbers (as strings)

```
0
-1
-0
1
99
100
255
256
-128
-129
32767
32768
65535
65536
2147483647
2147483648
-2147483648
-2147483649
9999999999999999
1e308
1e-308
NaN
Infinity
-Infinity
0.1 + 0.2
3.14159265358979323846
```

## Empty and Whitespace

```
(empty string — type nothing, just delete)

  (single space)
	(tab character)
\n
\r\n
\t\t\t

(multiple newlines)
```

Use `deleteCount` to clear the field, then type the whitespace string. Check if the field accepts it or trims it.

## Special Characters

```
<>
&amp;
"quotes"
'apostrophe'
`backtick`
\backslash
/forward/slash
|pipe
*asterisk*
(parentheses)
[brackets]
{braces}
#hashtag
@mention
$dollar
%percent
^caret
~tilde
```

## Injection Strings

```
<script>alert(1)</script>
<img src=x onerror=alert(1)>
'; DROP TABLE users; --
" OR 1=1 --
${7*7}
{{7*7}}
%s%s%s%s%s
%n%n%n%n%n
../../../etc/passwd
..\..\..\..\windows\system32
```

## Unicode Edge Cases

```
Héllo (accented Latin)
مرحبا (Arabic — RTL)
שלום (Hebrew — RTL)
こんにちは (Japanese)
你好 (Chinese)
🇺🇸 (flag emoji — regional indicators)
👨‍👩‍👧‍👦 (family emoji — ZWJ sequence)
é (e + combining acute — NFD form)
é (precomposed — NFC form)
a̐ (a + combining chandrabindu)
Z̤͔ͧ̑a̲̬l̶g̀o̫̞ (Zalgo text — excessive combining marks)
​ (zero-width space U+200B)
‮reversed‬ (RTL override U+202E)
﷽ (single character that renders very wide)
ﷺ (single Arabic ligature)
𝕳𝖊𝖑𝖑𝖔 (mathematical bold fraktur)
```

## Long Strings

```
(100 a's — test basic length)
aaaaaaaaaa...  (repeat 100x)

(1000 a's — test moderate length)
aaaaaaaaaa...  (repeat 1000x)

(10000 a's — test extreme length)
aaaaaaaaaa...  (repeat 10000x)

(1000 emoji — test memory with multi-byte)
😀😀😀😀😀...  (repeat 1000x)
```

For long strings, use `type_text` with a generated string of the target length. Watch for: layout overflow, truncation behavior, performance degradation, crashes.

## Format Strings

```
%s
%d
%n
%x
%@
{0}
${HOME}
${PATH}
$(whoami)
#{1+1}
%08x.%08x.%08x.%08x
AAAA%p%p%p%p
```

These can crash apps that pass user input directly to string formatting functions.

## iOS-Specific

```
tel://1234567890
sms://1234567890
mailto://test@test.com
facetime://test@test.com
maps://?q=test
itms-apps://itunes.apple.com
app-settings:
x-callback-url://test
myapp://deeplink/path
shortcuts://
```

URL scheme strings can trigger unexpected behavior if the app processes text field content as URLs.

## Null and Control Characters

```
\0 (null byte)
\a (bell)
\b (backspace)
\f (form feed)
\v (vertical tab)
\x00\x00\x00 (multiple null bytes)
\x1b[31m (ANSI escape — red text)
\x7f (delete character)
```

Note: `type_text` types character by character via the keyboard, so some control characters may not be typeable. If a character can't be typed, that's fine — skip it. The attempt itself may reveal interesting behavior.

## Realistic Messy Input

Values that look like pasted or autocorrected content:

```
https://example.com/path?utm_source=email&utm_medium=link&token=abc123def456
{"name": "test", "email": "a@b.c", "id": 42}
Name,Email,Phone\nAlice,a@b.c,555-1234
SGVsbG8gV29ybGQ= (base64 encoded "Hello World")
data:text/html,<h1>Hello</h1>
/Users/someone/.ssh/id_rsa
C:\Users\someone\Documents\passwords.txt
AKIAIOSFODNN7EXAMPLE (looks like an AWS key)
```

These simulate accidental pastes — content from clipboard, terminal output, file paths, credentials.

## Temporal Values

```
2038-01-19T03:14:07Z (Unix 32-bit overflow)
1970-01-01T00:00:00Z (Unix epoch)
1969-12-31T23:59:59Z (pre-epoch)
9999-12-31T23:59:59Z (max date)
0000-01-01 (year zero)
2026-02-30 (invalid day)
2026-13-01 (invalid month)
25:61:99 (invalid time)
America/New_York (timezone as string)
+14:00 (extreme timezone offset)
-12:00 (extreme negative timezone offset)
```

## Structured Data in Plain Fields

Type structured data into fields that expect plain text:

```
{"key": "value", "nested": {"deep": true}}
<root><child attr="val">text</child></root>
SELECT * FROM users WHERE id = 1;
key1=val1&key2=val2&key3=val3
["item1", "item2", "item3"]
BEGIN:VCARD\nFN:Test User\nEND:VCARD
Content-Type: text/html\r\n\r\n<h1>hi</h1>
```
