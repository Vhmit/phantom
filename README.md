# phantom-ci script

![Bash Shell](https://img.shields.io/badge/Shell-Bash-blue?style=for-the-badge&logo=gnu-bash)

A powerful and customizable Bash script for building Android ROMs with continuous integration (CI) support. This script automates the entire process, from syncing sources to uploading the final build and sending notifications to Telegram.

## Features

- **Automated Builds**: Fully automates the ROM building process.
- **Telegram Integration**: Sends real-time notifications for build status, progress, and completion.
- **Customizable Configuration**: Easily configure build options, Telegram settings, and API keys in a separate `vars.txt` file.
- **Interactive Setup**: Prompts for the device codename and others references if not specified in the configuration.
- **Error Handling**: Automatically detects build failures and sends detailed error logs to a designated Telegram chat or Katbin.
- **File Uploading**: Uploads build artifacts to Gofile/PixelDrain and includes download links in the final notification.

## Pre-requisites

Before using this script, ensure you have the following dependencies installed:

- `repo`
- `jq`
- `curl`
- `sha256sum`

## Configuration

1.  **Copy ci_aosp.sh** it to your local machine.
2.  **Create a `vars.txt` file** in the root of the project by copying the example:

    ```bash
    wget https://raw.githubusercontent.com/Vhmit/phantom-ci/master/ci_aosp.sh && chmod +x ci_aosp.sh
    ```

     ```bash
    wget https://raw.githubusercontent.com/Vhmit/phantom-ci/master/vars.txt
    ```

3.  **Fill in the required variables** in `vars.txt`:

    - `LUNCH_PREFIX`: Example: lineage, aosp.
    - `LUNCH_RELEASE`: Example: ap1a, ap2a (optional).
    - `CONFIG_TARGET`: Example: bacon, pixelos, derp.
    - `BOT_TOKEN`: Your Telegram bot token.
    - `CHAT_ID`: Your Telegram channel/group chat ID.
    - `TOPIC_ID`: Your Telegram group with topics (chat+topic id).
    - `PIXELDRAIN_API_TOKEN`: Your PixelDrain API key.

Obs: If both lunch variables remain empty, it will default to breakfast.

- Example: ```LUNCH_PREFIX=lineage (lunch lineage_device-buildtype)```
- Example: ```LUNCH_RELEASE=ap2a (lunch lineage_device-release-buildtype)``` optional.

This lunch_release is exclusive to A14/A15 ROMs, so it's not necessary for older Android versions.

## Usage

To run the script, use the following command:

```bash
./ci_aosp.sh device
```

To use the synchronization function before compilation, run:

```bash
./ci_aosp.sh -s
```

Obs: It hasn't been tested yet whether we can use synchronization and compilation at the same time, so I can check that in the future.

### Options

- `-s`, `--sync`: Sync only sources.
- `-h`, `--help`: Show the help message.
- `-t`, `--build-type`: eng/user/userdebug (default: userdebug).
- `-c`, `--clean`: Full clean build.
-  `-i`, `--installclean`: Installclean build.
-  `-j`, `--jobs`: Number of jobs (default: all).
- `-u`, `--upload`: Upload host: gofile/pdrain (default: gofile).
  
As you can see, I keep these parameters by default: https://github.com/Vhmit/phantom-ci/blob/c2cab7be2d5cfb1e53f2fd65b12e785c2c52240d/ci_aosp.sh#L25 https://github.com/Vhmit/phantom-ci/blob/c2cab7be2d5cfb1e53f2fd65b12e785c2c52240d/ci_aosp.sh#L26 https://github.com/Vhmit/phantom-ci/blob/c2cab7be2d5cfb1e53f2fd65b12e785c2c52240d/ci_aosp.sh#L27

If you agree with these parameters, set only your device as per the usage topic. If you want to change the parameters, modify the script to make it permanent or define it during execution:

```./ci_aosp.sh device -t user -j8 -u pixeldrain```

Obs: Remember to define the lunch, pdrain API (optional) and target variables in vars.txt; this will be required.

## Credits

- [hipexscape](https://github.com/hipexscape/Build-Script/blob/master/README.md) for template readme and references.
- [gustavomends](https://github.com/GustavoMends) through inspiration and many ideas.
