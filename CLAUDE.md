# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- Build: `alr build` (Alire resolves GNAT and the GtkAda dependency automatically)
- Run: `alr run` or `bin/mandelbrot` directly
- There is no test suite; correctness is checked by building (style/warnings
  are treated seriously — see below) and running the GUI.

This is an Alire crate (`alire.toml`), not a bare `gprbuild` project — always
build through `alr build`/`alr run` rather than invoking `gprbuild` directly,
so the GtkAda dependency and generated `config/mandelbrot_config.gpr` resolve
correctly. `alire/cache/`, `alire/build/`, and `config/` are gitignored,
regenerated content.

## Architecture

- `src/mandelbrot.adb` is a thin entry point that only calls
  `Mandelbrot_GUI.Run`.
- `src/mandelbrot_gui.ads`/`.adb` hold everything else: Mandelbrot
  generation, the colour palette, Cairo rendering, mouse-driven selection,
  and PNG export. All GUI state (`Bottom_Left`, `Top_Right`,
  `Display_Buffer`, `Surface`, the widgets) is declared at package-body
  level, not inside `Run`.
  - This is required, not stylistic: GtkAda signal callbacks (`On_Draw`,
    `On_Destroy`, `On_Button_Press`, etc.) are connected via `'Access`,
    and Ada's accessibility rules forbid taking `'Access` of a subprogram
    nested inside another subprogram for a library-level access-to-subprogram
    type. Declaring callbacks and the state they touch at package-body level
    (rather than nested inside `Run`) is what makes this legal.
- Rendering pipeline: `Generate_Set` fills `Display_Buffer` (colour indices)
  for the current corners; `Render_Buffer` maps those indices through
  `Palette` into a `RGB24_Array_Access` pixel buffer backing a Cairo
  `Image_Surface` (created once via `Create_For_Data_RGB24`). Subsequent
  updates mutate that same buffer in place and call
  `Cairo.Surface.Flush`/`Mark_Dirty` rather than recreating the surface.
  `On_Draw` just blits the cached surface (plus a rubber-band rectangle
  while dragging) — it never recomputes anything.
- Mouse-driven zoom (`On_Button_Press`/`On_Motion`/`On_Button_Release` on the
  `Gtk_Drawing_Area`) tracks a drag in pixel space via `Compute_Selection`,
  which forces the selection square and clamps it to the canvas. On release,
  the pixel rectangle is mapped back into the complex plane using the
  current scale factor and `Recalculate` reruns `Generate_Set` for the new
  corners.
- `Colour_Insdices` (note: misspelled in the original code, kept for
  consistency) is a small `Unsigned_8` subrange, not the full 0-255 range.
  `Hue_To_RGB` divides by `Colour_Insdices'Last` (not a hardcoded 255) so
  the full hue wheel always spans whatever that range currently is — if
  the range changes again, no other code needs to change.
- PNG export (`On_Save_Clicked`) converts the live Cairo surface to a
  `Gdk_Pixbuf` and saves it via `gdk_pixbuf_savev`, which is hand-imported
  with `pragma Import (C, ...)` because GtkAda's own `Gdk.Pixbuf.Save`
  binding only supports a single option key/value pair — not enough to
  attach both `tEXt::Bottom_Left` and `tEXt::Top_Right` metadata chunks.

## Working in this repo

- The project compiles with strict GNAT style switches (`-gnatyk -gnaty3
  -gnatya -gnatyl -gnatyn -gnatyr -gnaty-d`, from `mandelbrot.gpr`) and
  `-gnatwa` (all warnings). Keep new code warning-clean; a few pre-existing
  `(style) incorrect layout` notes on top-level declarations are known and
  not worth chasing.
- GtkAda API details (exact signal-connection idioms, event field names,
  `Chars_Ptr_Array` conventions for hand-imported C functions, etc.) are
  easiest to confirm by grepping the fetched sources under
  `alire/cache/dependencies/gtkada_*/src/` (generated bindings live in
  `src/generated/`) rather than guessing from general GTK knowledge —
  GtkAda's Ada API doesn't always match the C API 1:1.
- This environment has no `xdotool`/`ydotool`/`wtype` for scripting mouse
  input on Wayland, so interactive features (drag-to-zoom, file dialogs)
  can't be driven end-to-end automatically. Verify GTK plumbing by
  building, launching the app (`GDK_BACKEND=wayland bin/mandelbrot &`),
  and screenshotting with `grim`; verify hand-imported C bindings in
  isolation with a throwaway second `Main` added temporarily to
  `mandelbrot.gpr` (remove it and the source file afterward — don't leave
  test mains committed).
