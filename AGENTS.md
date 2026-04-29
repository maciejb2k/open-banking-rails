# AGENTS.md

Guide for agents working on this codebase. Add a new section per area as
conventions emerge — don't pad sections with content that isn't established
yet.

## Admin UI

Read before touching `app/views/admin/`. Goal: keep the panel consistent and
the component library from rotting into one-off divs.

### Source of truth

**`/admin/styleguide`** (`admin_styleguide_path`) renders every reusable
component with its variants. Read it before writing markup. Each partial's
API is in its first line as `<%# locals: (...) %>` — that's the signature.

```
app/views/admin/shared/
  components/   reusable UI primitives
  form/         form field wrappers
  icons/        inline SVGs (one per file)
```

Useful helpers live in `app/helpers/admin/` (`sort_link`, `sensitive*`,
`admin_nav_sections`). CSS utilities in `app/assets/tailwind/application.css`:
`.admin-section`, `.admin-card`, `.form-input`.

### Reference views

When in doubt, copy the shape of these:

- **Index** (filters + sortable table + pagination) — `bank_transactions/index.html.erb`
- **Show** (header + actions + cards + definition list) — `settings/bank_connections/show.html.erb`
- **Form** (new/edit) — `settings/tpp_credentials/_form.html.erb`
- **Auth** (centered, full-width submit) — `sessions/new.html.erb`

### Rules

1. **Read the styleguide first.** If the thing exists as a component, use it.
   Don't render markup that has a component (buttons, badges, cards, tables,
   form fields, callouts, filter chips/triggers, dropdown menus).
2. **Don't copy Tailwind class strings.** If you'd write the same 8+ class
   string twice, use an existing utility (`.form-input`, `.admin-section`) or
   extract a partial.
3. **Use the design tokens.** Colors via `bg-primary/10`, `text-destructive`
   etc. — never raw hex. Spacing/radii from the existing scale.
4. **Sensitive data must be wrapped.** IBANs, amounts, names, raw payloads,
   secrets — wrap in `sensitive(value)` / `sensitive_class` / `sensitive: true`
   prop. See `app/helpers/admin/privacy_helper.rb` for kinds (`:blur`,
   `:strong`, `:redact`, `:mask`).
5. **Icons live in `shared/icons/`.** Don't inline SVG.

### Extracting a new component

Bar: same chunk of markup appears **3+ times**, or has non-trivial
logic/Stimulus wiring that would otherwise be duplicated. Don't extract on
impulse — every component is one more thing to maintain.

When you do extract:

1. Put the partial in `shared/components/_<name>.html.erb`.
2. First line is `<%# locals: (...) %>` with keyword-style locals; second line
   a one-liner explaining the non-obvious bits.
3. Add a section to `app/views/admin/styleguide/index.html.erb` showing every
   variant — same PR.
4. Replace the existing 3+ usages in the same change.

### Building something custom (one-off)

If a need genuinely doesn't fit anything reusable and the extraction bar
isn't met, that's fine — but:

- Leave a comment above explaining **why** no shared component fits, and what
  would trigger extraction:
  ```erb
  <%# Custom: needs sticky-on-scroll. If a second case appears, extract _sticky_bar. %>
  ```
- Use existing utilities and tokens (see Rules 2–3). No new class strings, no
  raw colors.

### PR checklist

- [ ] Loaded `/admin/styleguide` and every page touched, in the browser.
- [ ] No hand-rolled buttons / badges / inputs / tables.
- [ ] Sensitive values wrapped.
- [ ] If a new shared partial was added: it's in the styleguide.
- [ ] If something custom was added: there's a comment justifying it.
