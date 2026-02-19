# Interesting Values Dictionary

Curated text inputs for `type_text` testing. When you encounter a text field, try values from at least 3 categories below. These are chosen to trigger common iOS bugs: layout overflow, encoding issues, parsing failures, and injection vulnerabilities.

## How to Use

1. First, type a normal value to confirm the field works
2. Clear it with `deleteCount` and try values from the categories below
3. After each value, check: Did the returned value match? Did the layout break? Did elements disappear?

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
