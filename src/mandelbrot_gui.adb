--  GtkAda user interface for displaying the Mandelbrot Display_Buffer.
--  Author    : David Haley
--  Created   : 05/09/2026
--  Last Edit : 07/09/2026

--  20260907 : Set calculation moved to Calculation_Engine, now uses multiple
--  cores.

with Ada.Text_IO;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed;
with System;
with Calculation_Engine; use Calculation_Engine;
with Interfaces; use Interfaces;
use Calculation_Engine.Complex_Numbers;

with Glib; use Glib;
with Glib.Error; use Glib.Error;
with Glib.Object; use Glib.Object;
with Gtkada.Types; use Gtkada.Types;
with Gtk.Window; use Gtk.Window;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Box; use Gtk.Box;
with Gtk.Label; use Gtk.Label;
with Gtk.Button; use Gtk.Button;
with Gtk.Dialog; use Gtk.Dialog;
with Gtk.File_Chooser; use Gtk.File_Chooser;
with Gtk.File_Chooser_Dialog; use Gtk.File_Chooser_Dialog;
with Gtk.File_Filter; use Gtk.File_Filter;
with Gtk.Message_Dialog; use Gtk.Message_Dialog;
with Gtk.Drawing_Area; use Gtk.Drawing_Area;
with Gtk.Enums; use Gtk.Enums;
with Gtk.Main;
with Gdk.Event; use Gdk.Event;
with Gdk.Pixbuf; use Gdk.Pixbuf;
with Cairo; use Cairo;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Surface;

package body Mandelbrot_GUI is

   Image_Size : constant := Display_Indices'Last - Display_Indices'First + 1;

   --  Colour_Indices 0 .. 254 are mapped to vivid, fully saturated colours
   --  around the hue wheel; 255 (the point never diverged) is displayed as
   --  black.

   type Palette_Arrays is array (Colour_Indices) of RGB24_Data;

   function Build_Palette return Palette_Arrays is

      Palette : Palette_Arrays;

      function Hue_To_RGB (Index : Colour_Indices) return RGB24_Data is

         Hue : constant Float :=
           360.0 * Float (Index) / Float (Colour_Indices'Last);
         Sector_Position : constant Float := Hue / 60.0;
         Sector : constant Natural :=
           Natural (Float'Floor (Sector_Position)) mod 6;
         Fraction : constant Float :=
           Sector_Position - Float'Floor (Sector_Position);
         Descending : constant Float := 1.0 - Fraction;

         function To_Byte (Value : Float) return Byte is
           (Byte (Natural (Value * 255.0)));

      begin -- Hue_To_RGB
         case Sector is
            when 0 =>
               return (Red => To_Byte (1.0), Green => To_Byte (Fraction),
                       Blue => To_Byte (0.0));
            when 1 =>
               return (Red => To_Byte (Descending), Green => To_Byte (1.0),
                       Blue => To_Byte (0.0));
            when 2 =>
               return (Red => To_Byte (0.0), Green => To_Byte (1.0),
                       Blue => To_Byte (Fraction));
            when 3 =>
               return (Red => To_Byte (0.0), Green => To_Byte (Descending),
                       Blue => To_Byte (1.0));
            when 4 =>
               return (Red => To_Byte (Fraction), Green => To_Byte (0.0),
                       Blue => To_Byte (1.0));
            when others =>
               return (Red => To_Byte (1.0), Green => To_Byte (0.0),
                       Blue => To_Byte (Descending));
         end case;
      end Hue_To_RGB;

   begin -- Build_Palette
      for I in Colour_Indices loop
         if I = Colour_Indices'Last then
            Palette (I) := (Red => 0, Green => 0, Blue => 0);
         else
            Palette (I) := Hue_To_RGB (I);
         end if;
      end loop; -- I in Colour_Indices
      return Palette;
   end Build_Palette;

   Palette : constant Palette_Arrays := Build_Palette;

   Pixel_Data : constant RGB24_Array_Access :=
     new RGB24_Array (0 .. Image_Size * Image_Size - 1);

   Bottom_Left : Complex;
   Top_Right : Complex;
   Surface : Cairo_Surface;

   Window : Gtk_Window;
   Drawing_Area : Gtk_Drawing_Area;
   Corner_Label : Gtk_Label;
   Save_Button : Gtk_Button;

   --  Mouse-driven area selection. A left-button drag defines the diagonal
   --  of a square (the drag is forced square, and clamped to the display),
   --  which is used to recompute Display_Buffer for the selected area.

   Dragging : Boolean := False;
   Start_X, Start_Y, Cur_X, Cur_Y : Gdouble := 0.0;

   type Selections (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Min_X, Min_Y, Side : Gdouble;
         when False =>
            null;
      end case;
   end record;

   function Compute_Selection return Selections is

      Dx : constant Gdouble := Cur_X - Start_X;
      Dy : constant Gdouble := Cur_Y - Start_Y;
      Extent : constant Gdouble := Gdouble'Max (abs Dx, abs Dy);
      Max_Pixel : constant Gdouble := Gdouble (Image_Size - 1);
      Limit_X : constant Gdouble :=
        (if Dx >= 0.0 then Max_Pixel - Start_X else Start_X);
      Limit_Y : constant Gdouble :=
        (if Dy >= 0.0 then Max_Pixel - Start_Y else Start_Y);
      Clamped : constant Gdouble :=
        Gdouble'Min (Extent, Gdouble'Min (Limit_X, Limit_Y));

   begin -- Compute_Selection
      if Clamped < 2.0 then
         return (Valid => False);
      else
         return (Valid => True,
                 Min_X => (if Dx >= 0.0 then Start_X else Start_X - Clamped),
                 Min_Y => (if Dy >= 0.0 then Start_Y else Start_Y - Clamped),
                 Side => Clamped);
      end if;
   end Compute_Selection;

   procedure Render_Buffer is

      -- Fills Pixel_Data from Display_Buffer and Palette and informs Cairo
      -- that the backing store of Surface has changed.

   begin -- Render_Buffer
      Cairo.Surface.Flush (Surface);
      for X in Display_Indices loop
         for Y in Display_Indices loop
            Pixel_Data (Y * Image_Size + X) :=
              Palette (Display_Buffer (X, Y));
         end loop; -- Y in Display_Indices
      end loop; -- X in Display_Indices
      Cairo.Surface.Mark_Dirty (Surface);
   end Render_Buffer;

   package Real_IO is new Ada.Text_IO.Float_IO (Real);

   function Format (Value : Real) return String is

      Buffer : String (1 .. 24);

   begin -- Format
      Real_IO.Put (Buffer, Value, Aft => 6, Exp => 0);
      return Ada.Strings.Fixed.Trim (Buffer, Left);
   end Format;

   procedure Update_Label is

   begin -- Update_Label
      Corner_Label.Set_Text
        ("Bottom Left: (" & Format (Bottom_Left.Re) & ", " &
         Format (Bottom_Left.Im) & ")   Top Right: (" &
         Format (Top_Right.Re) & ", " & Format (Top_Right.Im) & ")" &
         ASCII.LF &
         "Drag the left mouse button over the image to zoom into a" &
         " selected area.");
   end Update_Label;

   function Save_Pixbuf_With_Metadata
     (Pixbuf : in Gdk_Pixbuf; Filename : in String;
      Bottom_Left_Text, Top_Right_Text : in String) return Boolean is

      -- gdk_pixbuf_savev is not bound by GtkAda, so it is imported directly
      -- here in order to pass the corner coordinates as PNG tEXt chunks
      -- (option keys of the form "tEXt::<keyword>").

      function Internal_Savev
        (Pixbuf        : System.Address;
         Filename      : String;
         Format        : String;
         Option_Keys   : Chars_Ptr_Array;
         Option_Values : Chars_Ptr_Array;
         Error         : out Glib.Error.GError) return Gboolean;
      pragma Import (C, Internal_Savev, "gdk_pixbuf_savev");

      Keys : Chars_Ptr_Array :=
        "tEXt::Bottom_Left" + "tEXt::Top_Right" + Null_Ptr;
      Values : Chars_Ptr_Array :=
        Bottom_Left_Text + Top_Right_Text + Null_Ptr;
      Error : Glib.Error.GError;
      Result : Gboolean;

   begin -- Save_Pixbuf_With_Metadata
      Result := Internal_Savev (Get_Object (Pixbuf), Filename & ASCII.NUL,
                                 "png" & ASCII.NUL, Keys, Values, Error);
      Free (Keys);
      Free (Values);
      if Result = 0 then
         if Error /= null then
            Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
              "Failed to save " & Filename & ": " &
              Glib.Error.Get_Message (Error));
         end if;
      end if;
      return Result /= 0;
   end Save_Pixbuf_With_Metadata;

   procedure On_Save_Clicked (Self : access Gtk_Button_Record'Class) is

      pragma Unreferenced (Self);

      Dialog : Gtk_File_Chooser_Dialog;
      Filter : Gtk_File_Filter;
      Response : Gtk_Response_Type;
      Discard_Widget : Gtk.Widget.Gtk_Widget;
      pragma Unreferenced (Discard_Widget);

   begin -- On_Save_Clicked
      Gtk_New (Dialog, "Save as PNG", Window, Action_Save);
      Discard_Widget := Dialog.Add_Button ("Cancel", Gtk_Response_Cancel);
      Discard_Widget := Dialog.Add_Button ("Save", Gtk_Response_Accept);
      Dialog.Set_Current_Name ("mandelbrot.png");

      Gtk_New (Filter);
      Filter.Set_Name ("PNG images");
      Filter.Add_Pattern ("*.png");
      Dialog.Add_Filter (Filter);

      Response := Dialog.Run;
      if Response = Gtk_Response_Accept then
         declare

            Chosen_Name : constant String := Dialog.Get_Filename;

            Filename : constant String :=
              (if Chosen_Name'Length >= 4 and then
                  Chosen_Name (Chosen_Name'Last - 3 .. Chosen_Name'Last) =
                  ".png"
               then Chosen_Name else Chosen_Name & ".png");

            Pixbuf : constant Gdk_Pixbuf :=
              Get_From_Surface (Surface, 0, 0, Gint (Image_Size),
                                 Gint (Image_Size));

            Bottom_Left_Text : constant String :=
              "Bottom Left: (" & Format (Bottom_Left.Re) & ", " &
              Format (Bottom_Left.Im) & ")";

            Top_Right_Text : constant String :=
              "Top Right: (" & Format (Top_Right.Re) & ", " &
              Format (Top_Right.Im) & ")";

            Saved : Boolean;

         begin
            Saved := Save_Pixbuf_With_Metadata
              (Pixbuf, Filename, Bottom_Left_Text, Top_Right_Text);
            if not Saved then
               declare
                  Error_Dialog : Gtk_Message_Dialog;
                  Error_Response : Gtk_Response_Type;
                  pragma Unreferenced (Error_Response);
               begin
                  Gtk_New (Error_Dialog, Window, Modal, Message_Error,
                           Buttons_Close, "Failed to save " & Filename);
                  Error_Response := Error_Dialog.Run;
                  Error_Dialog.Destroy;
               end;
            end if;
         end;
      end if;
      Dialog.Destroy;
   end On_Save_Clicked;

   procedure Recalculate (New_Bottom_Left, New_Top_Right : in Complex) is

   begin -- Recalculate
      Bottom_Left := New_Bottom_Left;
      Top_Right := New_Top_Right;
      Generate_Set (Bottom_Left, Top_Right);
      Render_Buffer;
      Update_Label;
      Drawing_Area.Queue_Draw;
   end Recalculate;

   function On_Draw (Self : access Gtk_Widget_Record'Class;
                      Cr   : Cairo.Cairo_Context) return Boolean is

      pragma Unreferenced (Self);

      Selection : Selections;

   begin -- On_Draw
      Set_Source_Surface (Cr, Surface, 0.0, 0.0);
      Paint (Cr);
      if Dragging then
         Selection := Compute_Selection;
         if Selection.Valid then
            Cairo.Set_Source_Rgb (Cr, 1.0, 1.0, 1.0);
            Cairo.Set_Line_Width (Cr, 1.0);
            Cairo.Rectangle (Cr, Selection.Min_X, Selection.Min_Y,
                              Selection.Side, Selection.Side);
            Cairo.Stroke (Cr);
         end if;
      end if;
      return False;
   end On_Draw;

   procedure On_Destroy (Self : access Gtk_Widget_Record'Class) is

      pragma Unreferenced (Self);

   begin -- On_Destroy
      Gtk.Main.Main_Quit;
   end On_Destroy;

   function On_Button_Press (Self : access Gtk_Widget_Record'Class;
                              Event : Gdk_Event_Button) return Boolean is

      pragma Unreferenced (Self);

   begin -- On_Button_Press
      if Event.Button = 1 then
         Dragging := True;
         Start_X := Event.X;
         Start_Y := Event.Y;
         Cur_X := Event.X;
         Cur_Y := Event.Y;
         Drawing_Area.Queue_Draw;
      end if;
      return False;
   end On_Button_Press;

   function On_Motion (Self : access Gtk_Widget_Record'Class;
                        Event : Gdk_Event_Motion) return Boolean is

      pragma Unreferenced (Self);

   begin -- On_Motion
      if Dragging then
         Cur_X := Event.X;
         Cur_Y := Event.Y;
         Drawing_Area.Queue_Draw;
      end if;
      return False;
   end On_Motion;

   function On_Button_Release (Self : access Gtk_Widget_Record'Class;
                                Event : Gdk_Event_Button) return Boolean is

      pragma Unreferenced (Self);

      Selection : Selections;
      M, Width : Real;
      New_Bottom_Left, New_Top_Right : Complex;

   begin -- On_Button_Release
      if Dragging and then Event.Button = 1 then
         Dragging := False;
         Cur_X := Event.X;
         Cur_Y := Event.Y;
         Selection := Compute_Selection;
         if Selection.Valid then
            M := (Top_Right.Re - Bottom_Left.Re) / Real (Display_Indices'Last);
            New_Bottom_Left :=
              (Bottom_Left.Re + M * Real (Selection.Min_X),
               Bottom_Left.Im + M * Real (Selection.Min_Y));
            Width := M * Real (Selection.Side);
            New_Top_Right :=
              (New_Bottom_Left.Re + Width, New_Bottom_Left.Im + Width);
            Recalculate (New_Bottom_Left, New_Top_Right);
         else
            Drawing_Area.Queue_Draw;
         end if;
      end if;
      return False;
   end On_Button_Release;

   procedure Run is

      Vbox : Gtk_Box;

   begin -- Run
      Bottom_Left := (-2.0, -2.0);
      Top_Right := (2.0, 2.0);

      Surface := Create_For_Data_RGB24 (Pixel_Data, Gint (Image_Size),
                                         Gint (Image_Size));
      Generate_Set (Bottom_Left, Top_Right);
      Render_Buffer;

      Gtk.Main.Init;

      Gtk_New (Window, Window_Toplevel);
      Window.Set_Title ("Mandelbrot");
      Window.Set_Resizable (False);

      Gtk_New (Corner_Label);
      Update_Label;

      Gtk_New (Save_Button, "Save as PNG...");
      Save_Button.On_Clicked (On_Save_Clicked'Access);

      Gtk_New (Drawing_Area);
      Drawing_Area.Set_Size_Request (Gint (Image_Size), Gint (Image_Size));
      Drawing_Area.Add_Events
        (Button_Press_Mask or Button_Release_Mask or Button1_Motion_Mask);
      Drawing_Area.On_Draw (On_Draw'Access);
      Drawing_Area.On_Button_Press_Event (On_Button_Press'Access);
      Drawing_Area.On_Button_Release_Event (On_Button_Release'Access);
      Drawing_Area.On_Motion_Notify_Event (On_Motion'Access);

      Gtk_New (Vbox, Orientation_Vertical, 0);
      Vbox.Pack_Start (Corner_Label, Expand => False, Fill => False);
      Vbox.Pack_Start (Save_Button, Expand => False, Fill => False);
      Vbox.Pack_Start (Drawing_Area, Expand => True, Fill => True);

      Window.Add (Vbox);
      Window.On_Destroy (On_Destroy'Access);

      Window.Show_All;
      Gtk.Main.Main;
      End_Tasks;
   end Run;

end Mandelbrot_GUI;
