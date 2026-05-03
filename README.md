# sbox CLL Extractor

PowerShell script to extract server content from **s&box** `.cll` packages and optionally copy referenced assets.

## Features

- Lists available `.cll` packages from the s&box `_bin` directory.
- Automatically decompresses the selected package.
- Extracts text entries into a readable file tree.
- Deletes intermediate `.gz` and `.gmca` files by default after extraction.
- Can copy assets referenced by the package into `referenced_assets/`.
- Can copy the XML file associated with the package.

## Requirements

- Windows
- PowerShell 7 recommended
- A local **s&box** installation

By default, the script expects s&box to be installed in the standard Steam location:

```text
C:\Program Files (x86)\Steam\steamapps\common\sbox
```

If your installation is somewhere else, pass a custom `_bin` path with `-AssetsBinPath`.

## Installation

Clone the repository:

```powershell
git clone https://github.com/ArtanisInc/sbox-cll-extractor.git
cd sbox-cll-extractor
```

## Usage

Interactive mode:

```powershell
.\extract-sbox-cll.ps1
```

By default, the script looks for packages in the standard Steam s&box asset cache:

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
    └── asset-report.json    # asset copy report, when enabled
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
| `-AssetSearchRoots`        | Custom directories used to search for assets.       |
| `-KeepDecompressedBlob`    | Keeps `.gz` and `.gmca` files.                      |
| `-CopyXml`                 | Copies the associated XML file when found.          |
| `-Force`                   | Allows overwriting an existing output directory.    |

## Notes

- `.gz` and `.gmca` files are deleted automatically after extraction unless `-KeepDecompressedBlob` is used.
- `-Force` clears the existing package output folder before extracting again.
- Missing assets are listed in `asset-report.json` when `-IncludeReferencedAssets` is enabled.
- This script does not redistribute any s&box content or third-party binaries.
