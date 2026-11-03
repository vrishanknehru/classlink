# Week 4 : Journals Missing From the Docs Site

# MkDocs Navigation Indentation

## Error:

On the docs site the **Journals** heading showed with no
names under it, and the deploy step failed.

## Relevant Context

`docs/summary.md` lists the site navigation:

``` markdown
- Journals
  - [Vemula Manvi Smaran](journals/1024160111-vemula-manvi-smaran/index.md)
  - [Vrishank Nehru](journals/1024160109-vrishank-nehru/index.md)
```

## Key Observation

The nested items used two spaces. The navigation plugin
reads Markdown lists, where a nested item needs four
spaces.

## Solution

Indent the nested items four spaces:

``` markdown
- Journals
    - [Vemula Manvi Smaran](journals/1024160111-vemula-manvi-smaran/index.md)
    - [Vrishank Nehru](journals/1024160109-vrishank-nehru/index.md)
```

**Because**

With two spaces the items count as a separate list, so
the Journals section had no children and the build
failed.
