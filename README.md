# DVD Camera Bounce for OBS

Turn any OBS camera source into an old-school DVD screensaver. The source travels diagonally across the entire OBS canvas and bounces off every edge.

## Install

1. In OBS, add your camera normally with **Sources → + → Video Capture Device**.
2. Open **Tools → Scripts**.
3. Select the **Lua Scripts** tab, click **+**, and choose `dvd-camera.lua` from this folder.
4. Select your camera in **Camera source**.
5. Set the camera width, height, movement speed, and optional spin speed, then leave **Enable bouncing** checked.

The script follows the source into whichever scene is currently active. If that source is not present directly in the active scene, it simply waits until it is available again.

## Controls

- **Camera width / height:** Exact rendered size in canvas pixels. Different proportions will stretch the camera image.
- **Movement speed:** Travel speed in pixels per second.
- **Spin speed:** Rotation in degrees per second. Positive values spin clockwise, negative values spin counterclockwise, and `0` disables spinning.
- **Enable bouncing:** Pause or resume movement without unloading the script.
- **Reset to top-left:** Restarts the camera against the upper-left edges on the next animation tick.
- **Restore original camera & stop:** Stops the animation and restores the position, size, alignment, and rotation the source had before the script began moving it. Change a setting or toggle **Enable bouncing** off and on to start again.

## Notes

- Keep the camera source unlocked if you want to reposition it manually before enabling the animation.
- The script uses the base canvas size configured under **Settings → Video**, so it works with common canvas resolutions without additional setup.
- If the chosen camera is larger than the canvas, its position is pinned to that axis rather than moving outside the frame.
- While spinning, the script accounts for the rotated corners so the camera remains inside the canvas.
- The original transform is remembered separately for each scene while the script remains loaded.
