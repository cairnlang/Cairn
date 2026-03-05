# IR / DAG Visibility (v1)

Cairn now exposes a read-only IR graph export for file-mode programs.

This is an introspection feature, not a compilation backend, and it does not change runtime behavior.

## CLI

```bash
./cairn --emit-ir json <file.crn>
./cairn --emit-ir json --fn <name> <file.crn>
```

- `--emit-ir json`: emit parsed program graph JSON instead of evaluating code.
- `--fn <name>`: emit only one function/expr by name.

The exporter follows file-mode loading rules:
- recursive `IMPORT` resolution
- prelude auto-loading (unless `CAIRN_NO_PRELUDE=1`)

## JSON Shape (v1)

Top-level:

- `version` (`"cairn-ir-json-v1"`)
- `source` (expanded file path)
- `functions` (array)

Per function/expr:

- `name`
- `kind` (`"function"` or `"expr"`)
- `effect`
- `signature` (`type_params`, `params`, `returns`)
- `entry_node`
- `exit_nodes`
- `nodes` (typed node records)
- `edges` (typed edge records)

## Determinism

For identical source and parser/runtime version, emitted graph IDs and JSON ordering are deterministic.

This makes IR output suitable for regression checks and tooling diffs.

## Example

```bash
./cairn --emit-ir json --fn id examples/generics.crn
```

Example output excerpt:

```json
{
  "version": "cairn-ir-json-v1",
  "functions": [
    {
      "name": "id",
      "entry_node": "f1:entry",
      "exit_nodes": ["f1:exit"],
      "nodes": [
        {"id": "f1:entry", "kind": "entry"},
        {"id": "f1:t1", "kind": "literal", "literal_type": "int", "value": 1, "span": {"word": 12}},
        {"id": "f1:t2", "kind": "op", "op": "add", "span": {"word": 13}},
        {"id": "f1:exit", "kind": "exit"}
      ],
      "edges": [
        {"from": "f1:entry", "to": "f1:t1", "kind": "control"},
        {"from": "f1:t1", "to": "f1:t2", "kind": "control"},
        {"from": "f1:t2", "to": "f1:exit", "kind": "control"}
      ]
    }
  ]
}
```
