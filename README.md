# pngconvMZ

MZ-2500向け画像変換用のRubyコマンドラインツールです。PNG画像をMZ-2500向けのPNGプレビュー、BRDデータ、BSD BASIC loader、4096色用palette情報などへ変換します。

Git管理上の正式エントリーポイントは `pngconvMZ.rb` です。

## Repository Layout

```text
imagetrans/
  pngconvMZ.rb        # entry point
  pngconv_mz/         # implementation files
    conversion_result.rb
    conversion_runner.rb
    dither_cli.rb
    dither_reducer.rb
    image_loader.rb
  Gemfile
  README.md
  .gitignore
```

`imagetrans` 直下のフォルダは、`pngconv_mz/` だけをGit管理対象にします。`images/`, `outdir/`, `oldver/` などの作業用フォルダや素材フォルダは管理対象外です。

## Requirements

- Ruby
- Bundler
- Ruby gems
  - `chunky_png`
  - `color`

JPEG入力は、利用可能な環境では `jpeg` / `libjpeg-ruby` 系の `require 'jpeg'` に対応したgemを使います。Windows環境では、gemが無い場合でもPowerShell/System.Drawingで読み込みをフォールバックします。

依存gemを入れる場合:

```powershell
bundle install
```

Bundlerを使わずに直接入れる場合:

```powershell
gem install chunky_png color
```

## Usage

基本形:

```powershell
ruby .\pngconvMZ.rb [options] input.png|input.jpg [output_base]
```

例:

```powershell
ruby .\pngconvMZ.rb -m 16 --layout 320x200 --out-dir .\outdir .\images\source.png sample16
```

```powershell
ruby .\pngconvMZ.rb -m 16 --layout 320x200 --out-dir .\outdir .\images\source.jpg sample16
```

```powershell
ruby .\pngconvMZ.rb -m 512 -f B --layout split320x200 --out-dir .\outdir .\images\source.png sample512
```

```powershell
ruby .\pngconvMZ.rb -m 4096 --sort luminance --distance oklab --layout 640x400 --out-dir .\outdir .\images\source.png sample4096
```

GUI連携用のJSON出力:

```powershell
ruby .\pngconvMZ.rb --json --quiet -m 512 -f all --layout 320x200 --out-dir .\outdir .\images\source.png sample
```

PNGのみ出力:

```powershell
ruby .\pngconvMZ.rb --png-only -m 16 --layout 320x200 --out-dir .\outdir .\images\source.png sample_png
```

## Options

主なオプション:

- `-m`, `--mode MODE`
  - `8`, `16`, `512`, `4096`
- `-f`, `--fixed CHANNEL`
  - 512色モード用固定チャンネル
  - `R`, `G`, `B`, `all`
- `--layout MODE`
  - `640x400`, `640x200`, `320x200`, `split320x200`
- `--resize MODE`
  - `fit`, `keep`, `cut`
  - `fit`: 640x400へそのままリサイズ
  - `keep`: アスペクト比を維持し、不足部分を黒背景で埋める
  - `cut`: アスペクト比を維持し、中央から640x400比率で切り出す
- `-d`, `--method METHOD`
  - `floyd_steinberg`, `stucki`, `jarvis`, `no_dither`
- `--strength VALUE`
  - `0.0` to `1.0`
- `--distance MODE`
  - `rgb`, `lab`, `oklab`
- `-r`, `--remove MODE`
  - 16色モード用
  - `no_remove`, `removeBB`, `removeDW`, `removeBBDW`
- `-s`, `--sort MODE`
  - 4096色モード用
  - `no_sort`, `luminance`, `frequency`
- `--out-dir DIR`
  - 出力先フォルダ
- `--png-only`
  - PNGのみを出力し、BRD/BSD/palletなどのMZ向け生成物を作らない
- `--json`
  - 変換結果をJSONで出力
- `--quiet`
  - 通常ログ出力を抑制

詳細は以下で確認できます。

```powershell
ruby .\pngconvMZ.rb --help
```

## Output

モードやレイアウトに応じて以下を出力します。

- `.png`
  - 変換結果のプレビュー画像
- `.brd`
  - MZ向け画面データ
- `.bas.bsd`
  - BASIC loader
- `.pallet`
  - 4096色モード用palette情報

これらの変換結果は生成物なのでGit管理対象外です。

`split320x200` ではUpper/Lower用に `_u` / `_l` を含むファイル名を生成し、BSDは `_ul.bas.bsd` を生成します。

## Git Policy

Gitに含めるもの:

- `pngconvMZ.rb`
- `pngconv_mz/`
- `README.md`
- `.gitignore`
- `Gemfile`

Gitに含めないもの:

- `pngconv_mz/` 以外の直下フォルダ
- `.png`, `.brd`, `.bsd`, `.bas.bsd`, `.pallet` などの変換出力
- `.d88` などのディスクイメージ
- 古い実験版スクリプト
- GUI側プロジェクトのコピーや一時ファイル
- 個人環境依存の設定やエディタ用ファイル

初回にGit管理を開始する場合:

```powershell
cd D:\home\work\ruby\imagetrans
git init
git status
git add README.md .gitignore Gemfile pngconvMZ.rb pngconv_mz
git commit -m "Initial Ruby converter"
```
