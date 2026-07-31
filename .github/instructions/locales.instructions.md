---
description: "Use when adding, renaming or removing any user-visible text, label, button, flash message or error string in the hrz_cmdb plugin. All 11 locale YAML files must be updated together."
applyTo: "config/locales/**"
---
# Translation Rules

## All 11 files, always

Adding a key to only some locale files is a defect. Every new key must be added to
**all** of these, in the same nesting position:

`bg.yml`, `de.yml`, `el.yml`, `en.yml`, `hr.yml`, `hu.yml`, `pl.yml`, `ro.yml`,
`ru.yml`, `tr.yml`, `uk.yml`

The same applies to renames and deletions — apply them across all 11 files in one change.

## Key naming

- Plugin keys are namespaced under `hrz_cmdb.*`.
- Model attribute labels go under `activerecord.attributes.<table_name>.<column>`,
  keyed by the real column name including its prefix:

```yaml
activerecord:
  attributes:
    hrzcm_location:
      b_name_full: "Full name"
      j_part_of1_id: "Part of"
```

## Rules

- Never hard-code display text in `.erb`, `.js` or controller flash messages — use `l()`
  / `l(:key)` and add the key to all locale files.
- Quote every value with double quotes.
- Keep key order identical across files so diffs stay reviewable.
- Do not leave English placeholders in non-English files. Provide a real translation for
  each language; if a term is a proper noun or acronym (e.g. "CMDB", "CI"), keep it as-is.

## Verify before finishing

After adding keys, confirm the count matches in every file, e.g.:

```bash
grep -c "<new_key_name>" config/locales/*.yml
```

Every file must report the same non-zero count.
