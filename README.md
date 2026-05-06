# pngconvMZ

`pngconvMZ` は、RetroPC 向け画像変換のための Ruby コアです。現在は SHARP MZ-2500 系を中心に、機種ごとの差分を切り替えながら PNG/JPEG 画像を以下の形式へ変換できます。

- PNG プレビュー画像
- BRD データ
- BSD BASIC loader
- 4096色用 `.palette` 情報
- 必要に応じて D88 ディスクイメージ

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
    machine_profiles.rb
    mzd88.rb
    version.rb
  Gemfile
  README.md
  CHANGELOG.md
  .gitignore
```

`imagetrans` 直下では、`pngconv_mz/` を含む本体コードのみを Git 管理対象にし、`images/` などの作業用フォルダは管理対象外とする運用を想定しています。

## Supported Machines

現在の対応機種は以下です。

- `mz2500`
  - SHARP MZ-2500 向け
  - `8 / 16 / 512 / 4096` 色モードに対応
- `mz2861`
  - SHARP MZ-2861 向け
  - `8 / 16 / 4096` 色モードに対応
  - 4096色パレット設定時のチャンネル順と、BRD のビット並びが MZ-2500 と一部異なります

今後は、ここに機種プロファイルを追加していく形で他機種対応を広げる想定です。

## Machine Profiles

本ツールでは、機種ごとの以下の差分を `machine profile` として持っています。

- 使用可能な `mode`
- `mode` ごとの `layout`
- 固定色指定 (`fixed`) の可否
- パレット設定時のチャンネル順
- BRD 出力時のビット並び

そのため、CLI でも GUI でも、まず機種を選んでから有効なモードやレイアウトを絞り込む使い方になります。

## Mode and Layout Matrix

機種ごとに使える `mode` / `layout` は次のとおりです。

### MZ-2500

| Mode | Layout |
| --- | --- |
| `8` | `640x400`, `640x200`, `320x200` |
| `16` | `640x400`, `640x200`, `320x200` |
| `512` | `320x200`, `split320x200` |
| `4096` | `640x400`, `640x200`, `320x200` |

### MZ-2861

| Mode | Layout |
| --- | --- |
| `8` | `640x400`, `640x200` |
| `16` | `640x400`, `640x200` |
| `4096` | `640x400`, `640x200` |

補足:

- `mz2861` では `512` 色モードを使いません
- `mz2861` では `320x200` レイアウトを使いません
- `512` 色の `fixed` 指定は `mz2500` でのみ有効です

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
ruby .\pngconvMZ.rb --machine mz2500 -m 16 --layout 320x200 --out-dir .\outdir .\images\source.png sample16
```

```powershell
ruby .\pngconvMZ.rb --machine mz2500 -m 512 -f B --layout split320x200 --out-dir .\outdir .\images\source.png sample512
```

```powershell
ruby .\pngconvMZ.rb --machine mz2861 -m 4096 --layout 640x400 --out-dir .\outdir .\images\source.png sample2861
```

```powershell
ruby .\pngconvMZ.rb --machine mz2500 -m 4096 --sort luminance --distance oklab --layout 640x400 --out-dir .\outdir .\images\source.png sample4096
```

GUI 連携用の JSON 出力:

```powershell
ruby .\pngconvMZ.rb --json --quiet --machine mz2500 -m 512 -f all --layout 320x200 --out-dir .\outdir .\images\source.png sample
```

PNG のみ出力:

```powershell
ruby .\pngconvMZ.rb --png-only --machine mz2500 -m 16 --layout 320x200 --out-dir .\outdir .\images\source.png sample_png
```

## Options

主なオプション:

- `--machine MACHINE`
  - 指定値: `mz2500`, `mz2861` (default [`mz2500`])
  - 変換対象の機種を指定する。
  - これにより使用可能な `mode` / `layout` / `fixed` や、BRD / palette の解釈が切り替わる。
  - `mz2500`: MZ-2500 向けプロファイル
  - `mz2861`: MZ-2861 向けプロファイル
- `-m`, `--mode MODE`
  - 指定値: `8`, `16`, `512`, `4096` (default [`8`])
  - 各種変換モードの指定。これにより各種設定が行われる。モードにより無効になるオプションが発生する。
  - `8`: 標準16色のうち、従来の8bitパソコンで使われていた8色のみ使用して減色
  - `16`: 標準16色で減色
  - `512`: MZ-2500 の 320x200/256色表示系を利用した 512色相当モード
  - `4096`: 画像から15色パレット(+黒固定の16色)を自動抽出し、4096色系情報もあわせて出力
- `-f`, `--fixed CHANNEL`
  - 指定値: `R`, `G`, `B`, `all` (default [`R`])
  - 512色モード用固定チャンネル。
  - R/G/Bのうちどれか1つの最下位ビットを0固定にすることにより256色表示するための指定。
  - `R`: 赤チャンネルを固定して変換
  - `G`: 緑チャンネルを固定して変換
  - `B`: 青チャンネルを固定して変換
  - `all`: `R` / `G` / `B` の3パターンをまとめて出力
- `--layout MODE`
  - 指定値: `640x400`, `640x200`, `320x200`, `split320x200` (default [`640x400`])
  - 選択した機種で表示に使うレイアウトを指定する。
  - PNG出力のアスペクト比は元画像と合わない場合がある。
  - `640x400`: 640x400 の1画面として出力
  - `640x200`: 640x200 の1画面として出力
  - `320x200`: 320x200 の1画面として出力
  - `split320x200`: 320x200 を上下2枚に分けて出力し、320x400相当として扱う。実機では上下２枚合わせて表示される。
- `--resize MODE`
  - 指定値: `fit`, `keep`, `cut` (default [`fit`])
  - 入力される画像データを640x400サイズとしてどのように扱うか指定する。
  - `fit`: 640x400 へそのままリサイズ
  - `keep`: アスペクト比を維持し、不足部分を黒背景で埋める
  - `cut`: アスペクト比を維持し、中央から 640x400 比率で切り出す
- `-d`, `--method METHOD`
  - 指定値: `floyd_steinberg`, `stucki`, `jarvis`, `no_dither` (default [`floyd_steinberg`])
  - 誤差拡散手法の指定をする。
  - `floyd_steinberg`: 標準的な誤差拡散ディザ
  - `stucki`: 拡散範囲が広く、比較的なめらかに見えやすいディザ
  - `jarvis`: 拡散範囲が広いジャービス系ディザ
  - `no_dither`: ディザなしで最近傍色に置き換え
- `--strength VALUE`
  - 指定値: `0.0` to `1.0` (default [`1.0`])
  - ディザの誤差拡散の強さの指定をする。
  - `0.0` で拡散なし、`1.0` で標準強度。
- `--distance MODE`
  - 指定値: `rgb`, `lab`, `oklab` (default [`rgb`])
  - 減色時に、元画像の色とパレット色のどれが最も近いかを判定するための色距離計算方法を指定する。
  - `rgb`: RGB値の差でそのまま判定。単純で分かりやすい
  - `lab`: 人の見た目に近い色差で判定。明るさと色味のバランスを取りやすい
  - `oklab`: 見た目の自然さを重視した色差で判定。写真系に向くことが多い
- `-r`, `--remove MODE`
  - 指定値: `no_remove`, `removeBB`, `removeDW`, `removeBBDW` (default [`no_remove`])
  - 16色モード用。サンプリング時に邪魔になるグレー系の色をサンプリングテーブルから削除するための指定をする。
  - `no_remove`: 16色をそのまま使う
  - `removeBB`: 明るい黒系 (`BB`) を除外
  - `removeDW`: 暗い白系 (`DW`) を除外
  - `removeBBDW`: `BB` と `DW` の両方を除外
- `-s`, `--sort MODE`
  - 指定値: `no_sort`, `luminance`, `frequency` (default [`no_sort`])
  - 4096色モード用。サンプリングテーブルのソーティングルールを指定する。
  - `no_sort`: 抽出順をそのまま使う
  - `luminance`: 明るさ順で並べる
  - `frequency`: 出現頻度が高い色を優先して並べる
- `--out-dir DIR`
  - 指定値: 任意の出力先フォルダ (default [入力画像と同じフォルダ])
  - 出力先フォルダ
  - 指定しない場合は入力画像と同じフォルダへ出力
- `--png-only`
  - PNG のみを出力し、BRD/BSD/palette などの機種専用生成物を作らない。
  - 実機向けデータを出さず、プレビューPNGだけ確認したいときに使用。
- `--json`
  - 変換結果を JSON で出力
  - GUI連携や外部ツール連携向け
- `--quiet`
  - 通常ログ出力を抑制
  - `--json` と組み合わせて使用
- `--d88 PATH`
  - 指定値: 任意の `.d88` 出力パス (default [未指定])
  - 生成した `BRD` / `BSD` を D88 ディスクイメージへ格納する。
  - `--png-only` とは併用できない。
- `--d88-title TITLE`
  - 指定値: 任意のディスクタイトル文字列 (default [D88ファイル名から自動決定])
  - 新規 D88 作成時に使うディスクタイトルを指定する。
- `--d88-append-if-exists`
  - 既存の D88 ファイルがある場合はそこへ追加し、無い場合は新規作成する。
- `--d88-sidecar MODE`
  - 指定値: `keep`, `delete` (default [`keep`])
  - D88 生成後に `BRD` / `BSD` ファイルを残すか削除するかを指定する。

詳細は以下で確認できます。

```powershell
ruby .\pngconvMZ.rb --help
```

## 誤差拡散法について

`--method` で指定する `floyd_steinberg`, `stucki`, `jarvis` は、いずれも誤差拡散法 (error diffusion) に分類されます。これは、減色で失われる色や明るさの差を周囲のピクセルへ分配し、レトロPCの少ない色数でも写真やグラデーションをそれらしく見せるための手法です。

- `floyd_steinberg`
  - 比較的コンパクトな拡散カーネルを使う、代表的な誤差拡散法です。
  - 粒状感と階調のバランスが良く、レトロPC向け画像でも標準設定として使いやすい方式です。
- `jarvis`
  - Floyd-Steinberg より広い範囲へ誤差を分配する方式です。
  - 粒がやや細かく見えやすく、空や肌などのなだらかな面を滑らかに見せたい場合に向きます。
- `stucki`
  - Jarvis 系に近い、広めの範囲へ誤差を分配する方式です。
  - 細かな粒を保ちつつ階調を残しやすく、写真系の入力を自然に見せたい場合に向いています。
- `no_dither`
  - 誤差拡散を行わず、各ピクセルを最も近いパレット色へそのまま置き換えます。
  - パレットへの置き換わり方を素直に確認したい場合や、ディザの粒を出したくない絵柄の確認に向いています。

参考:

- [Error diffusion - Wikipedia](https://en.wikipedia.org/wiki/Error_diffusion)
- [Floyd–Steinberg dithering - Wikipedia](https://en.wikipedia.org/wiki/Floyd%E2%80%93Steinberg_dithering)
- [An adaptive algorithm for spatial greyscale (J-GLOBAL)](https://jglobal.jst.go.jp/en/detail?JGLOBAL_ID=201002004108891171)

## Output

モードやレイアウトに応じて以下を出力します。

- `.png`
  - 変換結果のプレビュー画像
- `.brd`
  - 機種向け画面データ
- `.bas.bsd`
  - BASIC loader
- `.palette`
  - 4096色モード用 palette 情報
- `.d88`
  - 必要に応じて生成する D88 ディスクイメージ

これらの変換結果は生成物なので Git 管理対象外です。

### split320x200 モード

`split320x200` は MZ-2500 用のレイアウトです。320x200 256色の画像データを上下に並べて 320x400 相当として扱います。

Upper/Lower 用に `_u` / `_l` を含む画像ファイル名のデータを生成し、対応する BSD ファイルとして `_c.bas.bsd` を生成します。

## Naming Notes

- 512色モードの固定色出力ファイル名は `_fixedR` / `_fixedG` / `_fixedB` ではなく `_FR` / `_FG` / `_FB` を使用します。
- `split320x200` の結合BSDファイル名は `_ul.bas.bsd` ではなく `_c.bas.bsd` を使用します。
- 例:
  - `sample_FR.png`
  - `sample_FR.brd`
  - `sample_FR.bas.bsd`
  - `sample_FR_u.brd`
  - `sample_FR_l.brd`
  - `sample_FR_c.bas.bsd`

## D88 Notes

- `--d88` を使用すると、生成した `BRD` / `BSD` を D88 ディスクイメージへ追加できます。
- 既定では、新規 D88 を作成します。
- `--d88-append-if-exists` を指定すると、既存 D88 ファイルがある場合はそこへ追加し、無い場合は新規作成します。
- `--d88-sidecar keep` を指定すると、D88追加後も `BRD` / `BSD` を残します。
- `--d88-sidecar delete` を指定すると、D88追加後に `BRD` / `BSD` を削除します。
- D88内部ファイル名は安全側の運用として **16 bytes以内** を前提にしています。
- ベース名が長い場合は、D88へ追加できないことがあるため、短い `output_base` を使ってください。

## Notes

本ツールは個人開発のソフトウェアです。動作確認は可能な範囲で行っていますが、すべての環境での動作を保証するものではありません。

生成されたファイルの利用や、実機・エミュレータでの読み込みは、利用者ご自身の責任で行ってください。重要なデータを扱う場合は、事前にバックアップを取ることをおすすめします。
