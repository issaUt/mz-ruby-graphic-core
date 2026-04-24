# pngconvMZ

`pngconvMZ` は、RetroPC 向け画像変換のための Ruby コアです。現在は SHARP MZ-2500 向け出力に対応しており、PNG/JPEG 画像を以下の形式へ変換できます。

- PNG プレビュー画像
- BRD データ
- BSD BASIC loader
- 4096色用 `.palette` 情報

Git 管理上の正式なエントリーポイントは `pngconvMZ.rb` です。

## Related Projects

- Ruby core: [mz-ruby-graphic-core](https://github.com/issaUt/mz-ruby-graphic-core)
- GUI frontend: [retropc-graphic-converter](https://github.com/issaUt/retropc-graphic-converter)
- Change log: [CHANGELOG.md](CHANGELOG.md)

GUI フロントエンドからこの Ruby スクリプトを呼び出して使うこともできます。

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
    version.rb
  Gemfile
  README.md
  .gitignore
```

`imagetrans` 直下では、`pngconv_mz/` を含む本体コードのみを Git 管理対象にし、`images/` などの作業用フォルダは管理対象外とする運用を想定しています。

## Requirements

- Ruby
- Bundler
- Ruby gems
  - `chunky_png`
  - `color`


## Install Ruby on Windows

本ツールを利用するには、Windows 上に Ruby 実行環境が必要です。

### Recommended Installer

Windows では RubyInstaller for Windows を推奨します。

https://rubyinstaller.org/

インストール時は以下を有効にしてください。

- `Add Ruby executables to your PATH`

インストール完了後、PowerShell またはコマンドプロンプトで確認します。

```powershell
ruby -v
```

### Confirmed Version

動作確認環境:

- Ruby 3.2.2

より新しい Ruby でも動作する可能性がありますが、問題がある場合は Ruby 3.2 系を推奨します。

### Install Bundler

```powershell
gem install bundler
```

### Install Required Gems

`Gemfile` を使う場合:

```powershell
bundle install
```

Bundler を使わずに個別導入する場合:

```powershell
gem install chunky_png color
```

### JPEG ライブラリについて

JPEG 入力は、利用可能な環境では `require 'jpeg'` に対応した JPEG gem を使います。Windows 環境では JPEG gem が無い場合でも、PowerShell/System.Drawing によるフォールバックで読み込みできます。

Windows では JPEG gem のネイティブビルドに失敗する環境があるため、`Gemfile` には JPEG gem を必須依存として追加していません。Windows 中心の利用では `chunky_png` と `color` のみで問題ありません。

WSL/Linux など Windows 以外で JPEG 入力を使う場合は、JPEG gem と `libjpeg` 開発パッケージが必要です。Ubuntu/WSL の例:

```bash
sudo apt update
sudo apt install build-essential libjpeg-dev
gem install jpeg
```

## Test Execution

以下でヘルプが表示されれば準備完了です。

```powershell
ruby .\pngconvMZ.rb --help
```

バージョン確認:

```powershell
ruby .\pngconvMZ.rb --version
```

GUI 連携向けの情報出力:

```powershell
ruby .\pngconvMZ.rb --info --json
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

GUI 連携用の JSON 出力:

```powershell
ruby .\pngconvMZ.rb --json --quiet -m 512 -f all --layout 320x200 --out-dir .\outdir .\images\source.png sample
```

PNG のみ出力:

```powershell
ruby .\pngconvMZ.rb --png-only -m 16 --layout 320x200 --out-dir .\outdir .\images\source.png sample_png
```

## Options

主なオプション:

- `-m`, `--mode MODE`
  - `8`, `16`, `512`, `4096`
  - `8`: MZ標準8色パレットで減色
  - `16`: MZ標準16色パレットで減色
  - `512`: MZ-2500 の 320x200/256色表示系を利用した 512色相当モード
  - `4096`: 画像から16色パレットを自動抽出し、4096色系情報もあわせて出力
- `-f`, `--fixed CHANNEL`
  - 512色モード用固定チャンネル
  - `R`, `G`, `B`, `all`
  - `R`: 赤チャンネルを固定して変換
  - `G`: 緑チャンネルを固定して変換
  - `B`: 青チャンネルを固定して変換
  - `all`: `R` / `G` / `B` の3パターンをまとめて出力
- `--layout MODE`
  - `640x400`, `640x200`, `320x200`, `split320x200`
  - `640x400`: 640x400 の1画面として出力
  - `640x200`: 640x200 の1画面として出力
  - `320x200`: 320x200 の1画面として出力
  - `split320x200`: 320x200 を上下2枚に分けて出力し、320x400相当として扱う
- `--resize MODE`
  - `fit`, `keep`, `cut`
  - `fit`: 640x400 へそのままリサイズ
  - `keep`: アスペクト比を維持し、不足部分を黒背景で埋める
  - `cut`: アスペクト比を維持し、中央から 640x400 比率で切り出す
- `-d`, `--method METHOD`
  - `floyd_steinberg`, `stucki`, `jarvis`, `no_dither`
  - `floyd_steinberg`: 標準的な誤差拡散ディザ
  - `stucki`: 拡散範囲が広く、比較的なめらかに見えやすいディザ
  - `jarvis`: 拡散範囲が広いジャービス系ディザ
  - `no_dither`: ディザなしで最近傍色に置き換え
- `--strength VALUE`
  - `0.0` to `1.0`
  - ディザの誤差拡散の強さ。`0.0` で拡散なし、`1.0` で標準強度
- `--distance MODE`
  - `rgb`, `lab`, `oklab`
  - `rgb`: RGB空間の距離で近い色を選ぶ
  - `lab`: Lab色空間で近い色を選ぶ
  - `oklab`: Oklab色空間で近い色を選ぶ
- `-r`, `--remove MODE`
  - 16色モード用
  - `no_remove`, `removeBB`, `removeDW`, `removeBBDW`
  - `no_remove`: 16色をそのまま使う
  - `removeBB`: 明るい黒系 (`BB`) を除外
  - `removeDW`: 暗い白系 (`DW`) を除外
  - `removeBBDW`: `BB` と `DW` の両方を除外
- `-s`, `--sort MODE`
  - 4096色モード用
  - `no_sort`, `luminance`, `frequency`
  - `no_sort`: 抽出順をそのまま使う
  - `luminance`: 明るさ順で並べる
  - `frequency`: 出現頻度が高い色を優先して並べる
- `--out-dir DIR`
  - 出力先フォルダ
  - 指定しない場合は入力画像と同じフォルダへ出力
- `--png-only`
  - PNG のみを出力し、BRD/BSD/palette などの MZ 向け生成物を作らない
  - 実機向けデータを出さず、プレビューPNGだけ確認したいときに使う
- `--json`
  - 変換結果を JSON で出力
  - GUI連携や外部ツール連携向け
- `--quiet`
  - 通常ログ出力を抑制
  - `--json` と組み合わせて使うと結果だけを扱いやすい

詳細は以下で確認できます。

```powershell
ruby .\pngconvMZ.rb --help
```

## Output

モードやレイアウトに応じて以下を出力します。

- `.png`
  - 変換結果のプレビュー画像
- `.brd`
  - MZ 向け画面データ
- `.bas.bsd`
  - BASIC loader
- `.palette`
  - 4096色モード用 palette 情報

これらの変換結果は生成物なので Git 管理対象外です。

### split320x200 モード

MZ-2500 では、320x200 256色の画像データを上下に並べて 320x400 256色として表示できます。`--layout split320x200` を指定した場合、このモードになります。

Upper/Lower 用に `_u` / `_l` を含む画像ファイル名のデータを生成し、MZ-2500 BASIC-M25 用の画像ファイルローダとなる BSD ファイル `_ul.bas.bsd` を生成します。

## Notes

本ツールは個人開発のソフトウェアです。動作確認は可能な範囲で行っていますが、すべての環境での動作を保証するものではありません。

生成されたファイルの利用や、実機・エミュレータでの読み込みは、利用者ご自身の責任で行ってください。重要なデータを扱う場合は、事前にバックアップを取ることをおすすめします。
