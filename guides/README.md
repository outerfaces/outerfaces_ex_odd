# Outerfaces ODD Guides

Welcome to the Outerfaces ODD (Outerfaces Dynamic Distribution) guides!

## Available Guides

### [Rev Pinning Quickstart](./REV_PINNING_QUICKSTART.md)
Learn how to implement rev-pinned, unbundled ESM architecture in your Phoenix application with Outerfaces. This guide covers:
- Setting up rev-pinned asset URLs for immutable caching
- Implementing service workers for automatic updates
- Configuring import maps for ES module resolution
- Building extended serve index plugs with advanced features

### [Import Rewriting and Token Transformation](./IMPORT_REWRITING.md)
Comprehensive guide to Outerfaces ODD's import rewriting system:
- How `[OUTERFACES_ODD_CDN]` and `[OUTERFACES_ODD_SPA]` tokens work
- JavaScript, CSS, and HTML transformation at runtime
- Setting up jsconfig.json for IDE autocomplete
- Import maps + rev pinning for native ESM
- Multi-port vs unified proxy mode
- Best practices and troubleshooting

## About Outerfaces ODD

Outerfaces ODD provides a framework for serving JavaScript applications with:
- **Rev-pinned URLs**: Assets are served with revision identifiers (`/__rev/<rev>/spa/...`) enabling aggressive caching
- **Service Worker Integration**: Automatic detection of new deployments and client reload
- **Import Map Support**: ES module resolution with rev-pinned paths
- **ROFL File Transformation**: Runtime transformation of `.rofl.js`, `.rofl.css`, and `.rofl.html` files with token replacement

## Contributing

If you have suggestions for new guides or improvements to existing ones, please open an issue or pull request in the outerfaces_ex_odd repository.

## Resources

- [Outerfaces ODD Documentation](https://hexdocs.pm/outerfaces_odd)
- [Outerfaces Core Documentation](https://hexdocs.pm/outerfaces)
- [Phoenix Framework](https://phoenixframework.org)
