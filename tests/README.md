# Image editor validation

Run `python3 tests/test_image_edit_ocr.py` on any development host. These regression
tests execute the SQL extracted from KayokoHistoryStore against an in-memory
database and check replacement, restore, late OCR completion and metadata isolation.

The GitHub Actions workflow **Image editor regression tests** runs both the SQLite
checks, real renderer tests, and native editor layout/interaction tests on iOS
Simulator. It can also be started manually.

`KayokoFingerImageRendererTests.m` contains pixel-level iOS XCTest regressions for
EXIF orientation, downsampling limits, reverse crop, masks, all privacy filters,
overlay aspect fit, and invalid inputs. Run `xcodegen generate --spec tests/project.yml`,
then test the `KayokoEditorTests` scheme in the generated project on an iOS Simulator.
The Theos build excludes the test sources. A full Xcode and
iOS Simulator/device runtime are required; Command Line Tools alone cannot run them.

`KayokoFingerEditorLayoutTests.m` links the production controller, canvas, dock and
renderer. A contained controller supplies deterministic safe areas for 430×932,
375×667, 320×568 and 844×390 point viewports. The tests wait for real image decoding,
check that every visible editing control fits the viewport, verify the bottom/right
dock and thumb-reachable actions in every mode, and exercise mode/tool, color,
stroke width and canvas lock changes. Only SpringBoard's localization provider and
the OCR service are stubbed; the shipped Chinese/English strings are copied into
the test bundle. Screenshots use a generated sample image rather than clipboard data.

CI retains screenshots for every viewport and mode in the
`editor-layout-screenshots` artifact, exported from XCTest's image attachments.
The complete `image-editor-test-results` artifact contains the `.xcresult` bundle.

Build the actual package with `THEOS=/path/to/theos ./build.sh rootless`. Check its
version/architecture and `/var/jb` payload with `dpkg-deb -f` and `dpkg-deb -c`;
inspect extracted dylibs with `lipo -info` and `otool -L`.

Device acceptance checklist (not covered by compilation):

- Long-press a historical image and open the sliders button beside Edit. Repeat
  from favorites; text previews must not display the new button.
- Draw, crop in either direction, add text, apply each mosaic/blur and solid cover,
  choose a photo overlay, pinch/drag, rotate and undo/redo. Confirm saved pixels
  match the preview, and Undo all + Done keeps the exact original file.
- OCR shows selectable text; copying it must leave the image editor open until
  Done/Cancel. Save then Restore Original must refresh OCR search results.
- Cancel/discard preserves history; Done updates only the selected history or
  favorite entry, preserves tags/notes, and exposes Restore Original.
- Force-close the panel/lock during processing; reopen another image and verify no
  late callback changes its preview. A failed save must keep edits available to retry.
- Test small-screen portrait and landscape, iOS 14 and iOS 16, plus a large photo.

5.0.5 regressions hold the real processing queue after finger-up and compare rendered
canvas/toolbar pixels before and during the pending commit, then verify the raster
handoff, zoom preservation and failure recovery. Real image/text preview tests check
that only the new image editor remains, Back is rightmost for images, and text editing
and its original Back placement still work. CI attaches stroke-before/pending/after
and image-preview screenshots.
