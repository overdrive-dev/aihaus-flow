# .cursor-plugin

Cursor plugin manifest directory. Cursor reads `plugin.json` here and treats
`pkg/.aihaus/` (the parent of this directory) as the plugin root, auto-discovering
sibling `rules/`, `skills/`, `agents/`, and `hooks/` directories.

See the project root `README.md` for install instructions, and
`pkg/.aihaus/rules/README.md` for the Cursor-specific usage guide.
