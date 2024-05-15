# Contribution Guidelines

## Pull request

When making a pull request, please include a description of the PR's purpose
and content.

If applicable, link to the corresponding issue.

## Continuous integration and development

### `pre-commit`

This repository uses [`pre-commit`].

It is recommended that you run [`pre-commit`] before making a PR, and ensure
that all checks are passing.

To run [`pre-commit`], follow the [`pre-commit`] installation guidelines, then
run:

```shell
pre-commit run --all-files --config cfg/pre-commit-config.yaml
```

[`pre-commit`]: https://github.com/pre-commit/pre-commit
