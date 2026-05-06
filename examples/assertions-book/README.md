# Assertions Book Examples

This directory is the canonical source for Assertions Book code examples.

| Directory | Contents |
| --------- | -------- |
| `assertions/src` | Assertion contracts imported into `phylax-docs/snippets` |
| `src` | Mock protocols and helper contracts used by those assertions |
| `test` | Reserved for focused example tests |

Before changing the docs snippets directly, update the matching Solidity file in
`assertions/src` and confirm the example profile still builds:

```bash
FOUNDRY_PROFILE=assertions-book forge build
```

After the change lands, run the `Import Credible Std Assertion Examples`
workflow in `phylaxsystems/phylax-docs` to refresh the docs snippets.
