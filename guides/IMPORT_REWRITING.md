# Import Rewriting and Token Transformation Guide

## Overview

Outerfaces ODD provides a powerful token-based import rewriting system that enables:
- Runtime URL transformation for CDN and SPA assets
- Rev-pinned asset paths for immutable caching
- Environment-agnostic code that works across deployment configurations
- IDE autocomplete support via jsconfig.json

## How Import Rewriting Works

### Token Syntax

Outerfaces ODD recognizes special tokens in `.rofl.js`, `.rofl.css`, and `.rofl.html` files:

| Token | Purpose | Example Transform |
|-------|---------|-------------------|
| `[OUTERFACES_ODD_CDN]` | CDN assets (libraries, vendored code) | `http://localhost:8011/__rev/abc123/cdn/` or `/__rev/abc123/cdn/` |
| `[OUTERFACES_ODD_SPA]` | SPA application code | `/__rev/abc123/spa/` |
| `[OUTERFACES_LOCAL_CDN]` | Legacy alias for ODD_CDN | Same as ODD_CDN |

**Important**: Tokens are only transformed in files with the `.rofl.*` extension.

### JavaScript Import Rewriting

The `OddCDNRoflJSPlug` transforms JavaScript imports at request time.

**Before transformation** (`index.rofl.js`):
```javascript
import { routes } from './routes/routes.js';
import {
  isPWA,
  hydrateRoutes
} from '[OUTERFACES_ODD_CDN]/outerfaces_js_core/0.1.0/lib/app-functions/index.js';
import { NavigationService } from '[OUTERFACES_ODD_CDN]/outerfaces_js_core/0.1.0/lib/services/navigation-service.js';
import { setAudioContext } from '[OUTERFACES_ODD_CDN]/tao_audio_js_core/0.1.0/lib/audio-context/index.js';
```

**After transformation** (served to browser):
```javascript
import { routes } from './routes/routes.js';
import {
  isPWA,
  hydrateRoutes
} from '/__rev/abc123/cdn/outerfaces_js_core/0.1.0/lib/app-functions/index.js';
import { NavigationService } from '/__rev/abc123/cdn/outerfaces_js_core/0.1.0/lib/services/navigation-service.js';
import { setAudioContext } from '/__rev/abc123/cdn/tao_audio_js_core/0.1.0/lib/audio-context/index.js';
```

**What gets rewritten**:
- `import ... from '[TOKEN]/path'` → Full URL with rev
- `export ... from '[TOKEN]/path'` → Full URL with rev
- Dynamic imports: `import('[TOKEN]/path')` → Full URL with rev
- Re-exports: `export * from '[TOKEN]/path'` → Full URL with rev

**What does NOT get rewritten**:
- Relative imports: `'./routes/routes.js'` stays as-is
- Bare specifiers: `'react'` stays as-is (use import maps instead)
- URLs without tokens: `'https://cdn.example.com/lib.js'` stays as-is

### CSS Import Rewriting

The `OddCDNRoflCSSPlug` transforms CSS `@import` and `url()` references.

**Before transformation** (`global-styles.rofl.css`):
```css
@import '[OUTERFACES_ODD_SPA]/styles/typography.css';
@import '[OUTERFACES_ODD_CDN]/normalize.css/8.0.1/normalize.css';

body {
  background-image: url('[OUTERFACES_ODD_SPA]/images/background.png');
}

.icon {
  background: url('[OUTERFACES_ODD_CDN]/icons/chevron.svg');
}
```

**After transformation**:
```css
@import '/__rev/abc123/spa/styles/typography.css';
@import '/__rev/abc123/cdn/normalize.css/8.0.1/normalize.css';

body {
  background-image: url('/__rev/abc123/spa/images/background.png');
}

.icon {
  background: url('/__rev/abc123/cdn/icons/chevron.svg');
}
```

### HTML Token Rewriting

The `OddCDNRoflHTMLPlug` transforms HTML `src` and `href` attributes.

**Before transformation** (`index.rofl.html`):
```html
<!DOCTYPE html>
<html>
  <head>
    <title>My App</title>
    <link rel="stylesheet" href="[OUTERFACES_ODD_SPA]/global-styles.css">
    <script type="module" src="[OUTERFACES_ODD_SPA]/index.rofl.js"></script>
  </head>
  <body>
    <div id="app"></div>
  </body>
</html>
```

**After transformation**:
```html
<!DOCTYPE html>
<html>
  <head>
    <base href="/">
    <script type="importmap" nonce="...">
    {
      "imports": {
        "/routes/": "/__rev/abc123/spa/routes/",
        "/services/": "/__rev/abc123/spa/services/"
      }
    }
    </script>
    <title>My App</title>
    <link rel="stylesheet" href="/__rev/abc123/spa/global-styles.css">
    <script type="module" src="/__rev/abc123/spa/index.rofl.js"></script>
  </head>
  <body>
    <div id="app"></div>
  </body>
</html>
```

Note: The extended `CDNConsumerServeIndex` also injects import maps and base tags.

## Import Maps + Rev Pinning

Import maps enable bare specifiers that resolve to rev-pinned paths.

### How It Works

1. **Extended ServeIndex injects import map** into HTML:
```html
<script type="importmap" nonce="xyz">
{
  "imports": {
    "/routes/": "/__rev/abc123/spa/routes/",
    "/services/": "/__rev/abc123/spa/services/",
    "/elements/": "/__rev/abc123/spa/elements/"
  }
}
</script>
```

2. **Your code uses bare imports**:
```javascript
import { AuthService } from '/services/auth-service.js';
import { LoginPage } from '/pages/login-page.js';
```

3. **Browser resolves via import map**:
```javascript
// Becomes:
import { AuthService } from '/__rev/abc123/spa/services/auth-service.js';
import { LoginPage } from '/__rev/abc123/spa/pages/login-page.js';
```

4. **Assets are immutably cached** because rev is in URL

### Benefits

- **No bundler needed**: Native ESM with import maps
- **Immutable caching**: Each rev has unique URLs
- **Zero runtime overhead**: Browser-native resolution
- **Atomic updates**: Rev change updates all imports instantly
- **Source maps work**: No transpilation, direct debugging

## IDE Support with jsconfig.json

Configure your IDE to understand ODD tokens and provide autocomplete.

### Basic Configuration

Create `jsconfig.json` in your project root:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "[OUTERFACES_ODD_CDN]/*": [
        "outerfaces/projects/odd_cdn/*"
      ],
      "[OUTERFACES_ODD_SPA]/*": [
        "outerfaces/projects/my_app/*"
      ],
      "/routes/*": [
        "outerfaces/projects/my_app/routes/*"
      ],
      "/services/*": [
        "outerfaces/projects/my_app/services/*"
      ],
      "/elements/*": [
        "outerfaces/projects/my_app/elements/*"
      ]
    }
  },
  "include": [
    "outerfaces/projects/**/*"
  ],
  "exclude": ["deps", "_build", "node_modules"]
}
```

### Multi-Project Configuration

For monorepos with multiple SPA projects:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "[OUTERFACES_ODD_CDN]/*": [
        "outerfaces/projects/odd_cdn/*"
      ],
      "[OUTERFACES_ODD_SPA]/*": [
        "outerfaces/projects/app_ui/*",
        "outerfaces/projects/admin_ui/*"
      ],
      "/routes/*": [
        "outerfaces/projects/app_ui/routes/*",
        "outerfaces/projects/admin_ui/routes/*"
      ],
      "/services/*": [
        "outerfaces/projects/app_ui/services/*",
        "outerfaces/projects/admin_ui/services/*"
      ]
    }
  },
  "include": [
    "outerfaces/projects/**/*"
  ]
}
```

### What This Enables

1. **Token autocomplete**: IDE resolves `[OUTERFACES_ODD_CDN]/...` imports
2. **Bare import autocomplete**: IDE resolves `/services/...` imports
3. **Go-to-definition**: Jump to source files from imports
4. **Rename refactoring**: Rename files and update all imports
5. **Type checking**: JSDoc types work across imports

### Example: Using ODD CDN Imports

**With jsconfig.json configured**:

```javascript
// IDE autocompletes library paths:
import {
  hydrateRoutes
} from '[OUTERFACES_ODD_CDN]/outerfaces_js_core/0.1.0/lib/app-functions/index.js';
//                                         ^ IDE suggests files here

// At runtime, transforms to:
// '/__rev/abc123/cdn/outerfaces_js_core/0.1.0/lib/app-functions/index.js'
```

**Without jsconfig.json**: No autocomplete, but still works at runtime.

## Multi-Port vs Unified Proxy Mode

Outerfaces supports two deployment architectures:

### Multi-Port Mode (Default)

**Architecture**:
- UI Port: 8012 (serves HTML, SPA assets)
- CDN Port: 8011 (serves vendored libraries, odd_cdn)
- API Port: 8010 (serves JSON API)

**Token transformation**:
```javascript
// [OUTERFACES_ODD_CDN] becomes:
'http://localhost:8011/__rev/abc123/cdn/...'

// [OUTERFACES_ODD_SPA] becomes:
'/__rev/abc123/spa/...'
```

**jsconfig.json**:
```json
{
  "compilerOptions": {
    "paths": {
      "[OUTERFACES_ODD_CDN]/*": ["outerfaces/projects/odd_cdn/*"],
      "[OUTERFACES_ODD_SPA]/*": ["outerfaces/projects/app_ui/*"]
    }
  }
}
```

**When to use**: Production deployments with separate CDN, complex architectures

### Unified Proxy Mode

**Architecture**:
- Single Port: 4001 (serves everything)
- `/spa/...` → SPA assets
- `/cdn/...` → CDN assets
- `/api/...` → API routes

**Token transformation**:
```javascript
// [OUTERFACES_ODD_CDN] becomes:
'/__rev/abc123/cdn/...'

// [OUTERFACES_ODD_SPA] becomes:
'/__rev/abc123/spa/...'
```

**Configuration**:
```elixir
plug(OddEnvironmentPlug,
  protocol: "http",
  host_names: ["localhost"],
  cdn_port: 4001,
  ui_port: 4001,
  api_port: 4001,
  unified_proxy_mode: true  # <- Enable unified mode
)

plug(CDNConsumerServeIndex,
  index_path: "...",
  static_root: "...",
  unified_proxy_mode: true  # <- Must match
)
```

**jsconfig.json**: Same as multi-port (IDE doesn't care about ports)

**When to use**: Simple deployments, local development, single-server setups

## Token Transformation Pipeline

Understanding the transformation order:

1. **Request arrives**: `/index.rofl.js`
2. **OddRevProxyPlug**: Checks if URL is `/__rev/<rev>/...`
   - If yes: Assigns `conn.assigns.outerfaces_rev = <rev>`
   - If no: Passes through
3. **OddCDNConsumerServeIndex**: Checks file type
   - `.rofl.js` → Call `OddCDNRoflJSPlug.transform_javascript_with_conn/3`
   - `.rofl.css` → Call `OddCDNRoflCSSPlug.transform_css_with_conn/3`
   - `.rofl.html` → Call `OddCDNRoflHTMLPlug.transform_html_cdn_tokens/3`
4. **Token rewriting**: Replace `[TOKEN]` with actual URLs
5. **Response sent**: Transformed content with rev-pinned URLs

## Best Practices

### 1. Use .rofl Extensions for Token Files

**Good**:
```
index.rofl.js      ✓ Tokens transformed
styles.rofl.css    ✓ Tokens transformed
index.rofl.html    ✓ Tokens transformed
```

**Bad**:
```
index.js           ✗ Tokens NOT transformed (served as-is)
styles.css         ✗ Tokens NOT transformed
```

### 2. Prefer Bare Imports with Import Maps

**Good** (with import maps):
```javascript
import { AuthService } from '/services/auth-service.js';
```

**Okay** (relative imports):
```javascript
import { AuthService } from './services/auth-service.js';
```

**Avoid** (hardcoded rev paths):
```javascript
import { AuthService } from '/__rev/abc123/spa/services/auth-service.js';
```

### 3. Use Tokens for Cross-Project Imports

**Good**:
```javascript
// Importing from vendored library
import { helper } from '[OUTERFACES_ODD_CDN]/my_lib/1.0.0/index.js';
```

**Bad**:
```javascript
// Hardcoded path - breaks if structure changes
import { helper } from '../../../odd_cdn/my_lib/1.0.0/index.js';
```

### 4. Configure jsconfig.json for IDE Support

Always create `jsconfig.json` in your project root for the best developer experience.

### 5. Use Source Maps for Debugging

Add `.map` files to your static patterns:

```elixir
defp default_static_patterns do
  [
    ~r{\.js$},
    ~r{\.css$},
    ~r{\.map$}  # <- Source maps
  ]
end
```

Source maps work natively because code isn't bundled or transpiled.

## Troubleshooting

### Tokens Not Being Transformed

**Symptom**: Seeing literal `[OUTERFACES_ODD_CDN]` in browser
**Cause**: File doesn't have `.rofl.*` extension
**Solution**: Rename `index.js` → `index.rofl.js`

### IDE Not Autocompleting

**Symptom**: No suggestions for token-based imports
**Cause**: Missing or incorrect `jsconfig.json`
**Solution**: Create `jsconfig.json` with correct paths

### Import Map Not Injected

**Symptom**: Bare imports fail in browser
**Cause**: Using stock `OddCDNConsumerServeIndex` instead of extended version
**Solution**: Create extended ServeIndex plug (see [REV_PINNING_QUICKSTART.md](./REV_PINNING_QUICKSTART.md))

### Cross-Origin Issues in Multi-Port Mode

**Symptom**: CORS errors when loading CDN assets
**Cause**: Different ports = different origins
**Solution**: Configure CORS headers in `OddCDNProviderContentSecurityPlug`

## Examples

### Example 1: Simple SPA with Import Maps

**index.rofl.html**:
```html
<!DOCTYPE html>
<html>
  <head>
    <title>My App</title>
    <script type="module" src="[OUTERFACES_ODD_SPA]/index.rofl.js"></script>
  </head>
  <body><div id="app"></div></body>
</html>
```

**index.rofl.js**:
```javascript
// Import map resolves bare specifiers
import { AuthService } from '/services/auth-service.js';
import { routes } from '/routes/routes.js';

console.log('App initialized');
```

**Transformed URLs**:
- HTML: `/__rev/abc123/spa/index.rofl.js`
- Imports: `/__rev/abc123/spa/services/auth-service.js`

### Example 2: Using Vendored Libraries

**index.rofl.js**:
```javascript
// Import from vendored library via ODD CDN token
import {
  hydrateRoutes
} from '[OUTERFACES_ODD_CDN]/outerfaces_js_core/0.1.0/lib/app-functions/index.js';

// Import from SPA code via bare specifier (import map)
import { routes } from '/routes/routes.js';

hydrateRoutes(routes);
```

**Transformed URLs**:
- Library: `/__rev/abc123/cdn/outerfaces_js_core/0.1.0/lib/app-functions/index.js`
- Routes: `/__rev/abc123/spa/routes/routes.js`

### Example 3: CSS with Asset References

**global-styles.rofl.css**:
```css
@import '[OUTERFACES_ODD_CDN]/normalize.css/8.0.1/normalize.css';

body {
  font-family: sans-serif;
  background-image: url('[OUTERFACES_ODD_SPA]/images/bg.png');
}
```

**Transformed**:
```css
@import '/__rev/abc123/cdn/normalize.css/8.0.1/normalize.css';

body {
  font-family: sans-serif;
  background-image: url('/__rev/abc123/spa/images/bg.png');
}
```

## See Also

- [REV_PINNING_QUICKSTART.md](./REV_PINNING_QUICKSTART.md) - Complete rev pinning setup
- [Outerfaces ODD Documentation](https://hexdocs.pm/outerfaces_odd)
- [ES Module Import Maps Spec](https://github.com/WICG/import-maps)
