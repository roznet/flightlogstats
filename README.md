# ![icon](https://raw.githubusercontent.com/roznet/flightlogstats/main/flightlogstats/Assets.xcassets/AppIcon.appiconset/icon-72.png) Flight Log Stats

This [app first version](https://apps.apple.com/us/app/flightlogstats/id1643324618) is currently on the app store, but still a work in progress.
You can also find more [information here](https://ro-z.net/blog/flightlogstats/).

## Introduction

Welcome to the first version of our app, which is currently available on the App Store. We are continuously improving it to provide you with the best possible experience.

## Objective

Our app simplifies the management of flight logs for Garmin G1000, Perspective, and Perspective+ systems. With our app, you can easily sync your flight logs and access them on multiple devices, so you can review and analyze them conveniently.

## How it Works

Log Synchronization: To sync your flight logs, simply connect your iPad to an SD card reader, press the + icon, and select the SD card from the file browser. All your logs will be imported and synced to your iCloud drive. Once your iPad has network connectivity, the files will be available on your Mac and iPhone. You can also access the logs via the Files app to sync them to your favorite service.

Log Review: With our app, you can view a summary of the imported logs and get information about each log. Additionally, the app has a fuel analysis feature, which allows you to enter a fuel target, and the app will estimate how much fuel you need to add to each tank to match the target. This is especially useful in Europe, where planes use gallons, but fuel needs to be measured in liters. You can also see a summary of your trips and statistics, such as how many miles, total time, and fuel used during your trips away from home.

## Development

Contributions to our app are welcome. To build the app:

1. Install [Git LFS](https://git-lfs.com) and run `git lfs pull`: the airport and waypoint database `python/nav.db` and the test logs `flightlogstatsTests/TestAssets/log_*.csv` are LFS objects.
2. Open `flightlogstats.xcodeproj` and build the `FlightLogStats` scheme. On the first build, `flightlogstats/secrets.json` (gitignored) is created from `flightlogstats/secrets.sample.json`; fill in your own FlySto keys there to use the upload.
3. Run the unit tests (hosted in the app, so they need a simulator):

```
xcodebuild test -project flightlogstats.xcodeproj -scheme FlightLogStats \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FlightLogStatsTests CODE_SIGNING_ALLOWED=NO
```

`python/nav.db` is rebuilt with `python/make_nav_db.py`. The design docs in `designs/` (start with `designs/INDEX.md`) describe the architecture and the known issues.

## Caveat

Please note that our app has only been tested with the logs from one aircraft, an SR22 with Garmin Perspective+. Therefore, we recommend using it as a supplementary tool and not as a primary planning tool. Always independently verify all calculations made by the app.

Thank you for using our app. If you have any feedback or suggestions, please feel free to contact us. We are committed to providing you with the best possible experience.
