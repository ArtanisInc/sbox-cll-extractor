# sbox CLL Extractor

PowerShell script to extract server content from **s&box** `.cll` packages and optionally copy/decompile referenced assets.

## Features

- Lists available `.cll` packages from the s&box `_bin` directory.
- Automatically decompresses the selected package.
- Extracts text entries into a readable file tree.
- Deletes intermediate `.gz` and `.gmca` files by default after extraction.
- Can copy assets referenced by the package into `referenced_assets/`.
- Can decompile compiled `*_c` assets into `decompiled_assets/` with `Source2Viewer-CLI.exe`.
- Can copy the XML file associated with the package.

> Decompilation depends on ValveResourceFormat support for each compiled asset type. Some s&box `.vmat_c`, `.prefab_c`, or `.sound_c` files may fail to decompile with the current ValveResourceFormat release. When that happens, the original compiled assets are still copied to `referenced_assets/`, and failures are recorded in `asset-report.json`.

## Requirements

- Windows
- PowerShell 7 recommended
- A local **s&box** installation
- Optional for decompilation:
  - `Source2Viewer-CLI.exe`
  - its required DLL/runtime files

> Third-party binaries such as `Source2Viewer-CLI.exe` and `.dll` files are not included in this repository. Download ValveResourceFormat from the official releases page: <https://github.com/ValveResourceFormat/ValveResourceFormat/releases>. Place `Source2Viewer-CLI.exe` and its DLL files locally next to the script if you want to use asset decompilation.

## Installation

Clone the repository:

```powershell
git clone <repository-url>
cd sbox
```

If you want to use decompilation, download ValveResourceFormat from <https://github.com/ValveResourceFormat/ValveResourceFormat/releases>, then place `Source2Viewer-CLI.exe` and its DLL files in the same folder as `extract-sbox-cll.ps1`, or provide a custom path with `-VrfCliPath`.

## Usage

Interactive mode:

```powershell
.\extract-sbox-cll.ps1
```

By default, the script looks for packages in:

```text
C:\Program Files (x86)\Steam\steamapps\common\sbox\download\assets\_bin
```

Extracted files are written to:

```text
.\extracted_packages
```

For each package, the output folder is organized as follows:

```text
extracted_packages/
└── package_name/
    ├── <extracted source files and folders>
    ├── referenced_assets/   # copied referenced assets, when enabled
    ├── decompiled_assets/   # decompiled Source 2 assets, when enabled
    └── asset-report.json    # asset copy/decompile report, when enabled
```

## Examples

Extract a package selected from the list:

```powershell
.\extract-sbox-cll.ps1
```

Filter packages by name:

```powershell
.\extract-sbox-cll.ps1 -Filter "*my_package*"
```

Extract a specific package:

```powershell
.\extract-sbox-cll.ps1 -PackagePath "C:\path\to\package_xxx.cll"
```

Overwrite an existing output folder:

```powershell
.\extract-sbox-cll.ps1 -PackagePath "C:\path\to\package_xxx.cll" -Force
```

Include referenced assets:

```powershell
.\extract-sbox-cll.ps1 -IncludeReferencedAssets
```

Include and decompile compiled assets:

```powershell
.\extract-sbox-cll.ps1 -IncludeReferencedAssets -DecompileCompiledAssets
```

Use a custom Source2Viewer path:

```powershell
.\extract-sbox-cll.ps1 -DecompileCompiledAssets -VrfCliPath "C:\tools\Source2Viewer-CLI.exe"
```

Keep intermediate `.gz` and `.gmca` files:

```powershell
.\extract-sbox-cll.ps1 -KeepDecompressedBlob
```

## Main Parameters

| Parameter                  | Description                                         |
| -------------------------- | --------------------------------------------------- |
| `-AssetsBinPath`           | Directory containing `.cll` packages.               |
| `-OutputRoot`              | Output directory for extracted files.               |
| `-Filter`                  | Name filter used to select a package.               |
| `-Index`                   | Package index to extract from the interactive list. |
| `-PackagePath`             | Direct path to a `.cll` file.                       |
| `-IncludeReferencedAssets` | Copies referenced assets into `referenced_assets/` when found. |
| `-DecompileCompiledAssets` | Decompiles `*_c` assets into `decompiled_assets/` with Source2Viewer. |
| `-AssetSearchRoots`        | Custom directories used to search for assets.       |
| `-VrfCliPath`              | Path to `Source2Viewer-CLI.exe`.                    |
| `-KeepDecompressedBlob`    | Keeps `.gz` and `.gmca` files.                      |
| `-CopyXml`                 | Copies the associated XML file when found.          |
| `-Force`                   | Allows overwriting an existing output directory.    |

## Notes

- `.gz` and `.gmca` files are deleted automatically after extraction unless `-KeepDecompressedBlob` is used.
- `-Force` clears the existing package output folder before extracting again.
- Missing assets and decompilation failures are listed in `asset-report.json` when `-IncludeReferencedAssets` is enabled.
- Failed decompilations are reported without leaving empty output folders.
- This script does not redistribute any s&box content or third-party binaries.
