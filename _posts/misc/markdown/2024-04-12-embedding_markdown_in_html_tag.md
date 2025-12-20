---
layout: post
title:  "embedding markdown in HTML tag"
author: fuqiang
date:   2024-04-12 10:53:00 +0800
categories: [misc, markdown]
tags: markdown html-details
---

## ISSUE

When I try to use the markdown syntax in `<details>` HTML tags, for example,
`code blocks`, encounter the problem of code blocks that cannot be rendered.

The source code is as follows:

```html
<details>
<summary> aaa </summary>
` ` `cpp
int a = 1;
` ` `

</details> 
```



> **\`** char seems unable to be translated in code block, so I added space
> characters between them
{: .prompt-warning}

It will display in browser as follows:

---
---

<details>
<summary>aaa</summary>

```cpp
int a = 1;
```

</details>

---
---


### SOLUTION

This issue seems to occur in the kramdowm markup process, rather than in GFM:
* [GFM allows embedding HTML inside Markdown][1]
* [Embedding Markdown in Jekyll HTML][1]

And in the link [Embedding Markdown in Jekyll HTML][2], a solution is provided:

Use `<details markdown="1">` instead  `<details>`.

It will run as expected 

---
---

<details markdown="1">
<summary>aaa</summary>

```cpp
int a = 1;
```

</details>
---
---
[details css]: https://developer.mozilla.org/en-US/docs/Web/HTML/Element/details
[1]: https://gist.github.com/scmx/eca72d44afee0113ceb0349dd54a84a2
[2]: https://stackoverflow.com/questions/15917463/embedding-markdown-in-jekyll-html
