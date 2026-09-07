--  GtkAda user interface for displaying the Mandelbrot Display_Buffer.
--  Author    : David Haley
--  Created   : 05/09/2026
--  Last Edit : 07/09/2026

--  20260907 : Set calculation moved to Calculation_Engine, now uses multiple
--  cores.

--  20260907 : Added Reset Selection, Previous Selection, Cancel Selection
--  and Selection OK buttons; a dragged selection square now requires
--  Selection OK before it is recalculated and displayed.

with Ada.Text_IO;
with Ada.Strings; use Ada.Strings;
with Ada.Strings.Fixed;
with GNAT.Source_Info;
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

   Initial_Bottom_Left : constant Complex := (-2.0, -2.0);
   Initial_Top_Right : constant Complex := (2.0, 2.0);

   Bottom_Left : Complex;
   Top_Right : Complex;
   Previous_Bottom_Left : Complex := Initial_Bottom_Left;
   Previous_Top_Right : Complex := Initial_Top_Right;
   Surface : Cairo_Surface;

   Window : Gtk_Window;
   Drawing_Area : Gtk_Drawing_Area;
   Corner_Label : Gtk_Label;
   Save_Button : Gtk_Button;
   Help_Button : Gtk_Button;
   Reset_Button : Gtk_Button;
   Previous_Button : Gtk_Button;
   Cancel_Button : Gtk_Button;
   Selection_OK_Button : Gtk_Button;

   --  Mouse-driven area selection. A left-button drag defines the diagonal
   --  of a square (the drag is forced square, and clamped to the display).
   --  On release, a valid square is held Pending until Selection OK is
   --  clicked (which recomputes Display_Buffer for the selected area) or
   --  Cancel Selection is clicked (which discards it).

   type Selection_States is (No_Selection, Dragging, Pending);
   Selection_State : Selection_States := No_Selection;
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
         Format (Top_Right.Re) & ", " & Format (Top_Right.Im) & ")");
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

      Old_Bottom_Left : constant Complex := Bottom_Left;
      Old_Top_Right : constant Complex := Top_Right;

   begin -- Recalculate
      Bottom_Left := New_Bottom_Left;
      Top_Right := New_Top_Right;
      Previous_Bottom_Left := Old_Bottom_Left;
      Previous_Top_Right := Old_Top_Right;
      Previous_Button.Set_Sensitive (True);
      Generate_Set (Bottom_Left, Top_Right);
      Render_Buffer;
      Update_Label;
      Drawing_Area.Queue_Draw;
   end Recalculate;

   type Corner_Pair is record
      Bottom_Left, Top_Right : Complex;
   end record;

   function Corners_From_Selection (S : in Selections) return Corner_Pair
     with Pre => S.Valid is

      M : constant Real :=
        (Top_Right.Re - Bottom_Left.Re) / Real (Display_Indices'Last);
      New_Bottom_Left : constant Complex :=
        (Bottom_Left.Re + M * Real (S.Min_X),
         Bottom_Left.Im + M * Real (S.Min_Y));
      Width : constant Real := M * Real (S.Side);

   begin -- Corners_From_Selection
      return (Bottom_Left => New_Bottom_Left,
              Top_Right => (New_Bottom_Left.Re + Width,
                             New_Bottom_Left.Im + Width));
   end Corners_From_Selection;

   function On_Draw (Self : access Gtk_Widget_Record'Class;
                      Cr   : Cairo.Cairo_Context) return Boolean is

      pragma Unreferenced (Self);

      Selection : Selections;

   begin -- On_Draw
      Set_Source_Surface (Cr, Surface, 0.0, 0.0);
      Paint (Cr);
      if Selection_State /= No_Selection then
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
         Selection_State := Dragging;
         Cancel_Button.Set_Sensitive (False);
         Selection_OK_Button.Set_Sensitive (False);
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
      if Selection_State = Dragging then
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

   begin -- On_Button_Release
      if Selection_State = Dragging and then Event.Button = 1 then
         Cur_X := Event.X;
         Cur_Y := Event.Y;
         Selection := Compute_Selection;
         if Selection.Valid then
            Selection_State := Pending;
            Cancel_Button.Set_Sensitive (True);
            Selection_OK_Button.Set_Sensitive (True);
         else
            Selection_State := No_Selection;
         end if;
         Drawing_Area.Queue_Draw;
      end if;
      return False;
   end On_Button_Release;

   procedure On_Reset_Clicked (Self : access Gtk_Button_Record'Class) is

      pragma Unreferenced (Self);

   begin -- On_Reset_Clicked
      Selection_State := No_Selection;
      Cancel_Button.Set_Sensitive (False);
      Selection_OK_Button.Set_Sensitive (False);
      Recalculate (Initial_Bottom_Left, Initial_Top_Right);
   end On_Reset_Clicked;

   procedure On_Previous_Clicked (Self : access Gtk_Button_Record'Class) is

      pragma Unreferenced (Self);

   begin -- On_Previous_Clicked
      Selection_State := No_Selection;
      Cancel_Button.Set_Sensitive (False);
      Selection_OK_Button.Set_Sensitive (False);
      Recalculate (Previous_Bottom_Left, Previous_Top_Right);
   end On_Previous_Clicked;

   procedure On_Cancel_Clicked (Self : access Gtk_Button_Record'Class) is

      pragma Unreferenced (Self);

   begin -- On_Cancel_Clicked
      Selection_State := No_Selection;
      Cancel_Button.Set_Sensitive (False);
      Selection_OK_Button.Set_Sensitive (False);
      Drawing_Area.Queue_Draw;
   end On_Cancel_Clicked;

   procedure On_Selection_OK_Clicked
     (Self : access Gtk_Button_Record'Class) is

      pragma Unreferenced (Self);

      Selection : constant Selections := Compute_Selection;
      Corners : Corner_Pair;

   begin -- On_Selection_OK_Clicked
      if Selection_State = Pending and then Selection.Valid then
         Corners := Corners_From_Selection (Selection);
         Selection_State := No_Selection;
         Cancel_Button.Set_Sensitive (False);
         Selection_OK_Button.Set_Sensitive (False);
         Recalculate (Corners.Bottom_Left, Corners.Top_Right);
      end if;
   end On_Selection_OK_Clicked;

   procedure On_Help_Clicked (Self : access Gtk_Button_Record'Class) is

      pragma Unreferenced (Self);

      Dialog : Gtk_Message_Dialog;
      Response : Gtk_Response_Type;
      pragma Unreferenced (Response);

   begin -- On_Help_Clicked
      Gtk_New
        (Dialog, Window, Modal, Message_Info, Buttons_Close,
         "Drag the left mouse button over the image to select a square" &
         " area, then use the buttons below:" & ASCII.LF & ASCII.LF &
         "Selection OK: zoom into the selected area." & ASCII.LF &
         "Cancel Selection: discard the current selection." & ASCII.LF &
         "Reset Selection: return to the full initial view." & ASCII.LF &
         "Previous Selection: return to the previous view." & ASCII.LF &
         "Save as PNG...: save the current image, with the corner" &
         " coordinates embedded as metadata." & ASCII.LF & ASCII.LF &
         "Build date: " & GNAT.Source_Info.Compilation_ISO_Date &
         ASCII.LF & ASCII.LF &
         "Credits: David Haley and Claude (Anthropic).");
      Response := Dialog.Run;
      Dialog.Destroy;
   end On_Help_Clicked;

   procedure Run is

      Vbox : Gtk_Box;
      Selection_Box : Gtk_Box;

   begin -- Run
      Bottom_Left := Initial_Bottom_Left;
      Top_Right := Initial_Top_Right;

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

      Gtk_New (Reset_Button, "Reset Selection");
      Reset_Button.On_Clicked (On_Reset_Clicked'Access);

      Gtk_New (Previous_Button, "Previous Selection");
      Previous_Button.On_Clicked (On_Previous_Clicked'Access);
      Previous_Button.Set_Sensitive (False);

      Gtk_New (Cancel_Button, "Cancel Selection");
      Cancel_Button.On_Clicked (On_Cancel_Clicked'Access);
      Cancel_Button.Set_Sensitive (False);

      Gtk_New (Selection_OK_Button, "Selection OK");
      Selection_OK_Button.On_Clicked (On_Selection_OK_Clicked'Access);
      Selection_OK_Button.Set_Sensitive (False);

      Gtk_New (Save_Button, "Save as PNG...");
      Save_Button.On_Clicked (On_Save_Clicked'Access);

      Gtk_New (Help_Button, "Help");
      Help_Button.On_Clicked (On_Help_Clicked'Access);

      Gtk_New (Selection_Box, Orientation_Horizontal, 0);
      Selection_Box.Pack_Start
        (Reset_Button, Expand => False, Fill => False);
      Selection_Box.Pack_Start
        (Previous_Button, Expand => False, Fill => False);
      Selection_Box.Pack_Start
        (Cancel_Button, Expand => False, Fill => False);
      Selection_Box.Pack_Start
        (Selection_OK_Button, Expand => False, Fill => False);
      --  Pack_End places each new child further from the box's end than
      --  the previous one, so Help_Button (packed first) ends up at the
      --  far right with Save_Button to its left.
      Selection_Box.Pack_End (Help_Button, Expand => False, Fill => False);
      Selection_Box.Pack_End (Save_Button, Expand => False, Fill => False);

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
      Vbox.Pack_Start (Selection_Box, Expand => False, Fill => False);
      Vbox.Pack_Start (Drawing_Area, Expand => True, Fill => True);

      Window.Add (Vbox);
      Window.On_Destroy (On_Destroy'Access);

      Window.Show_All;
      Gtk.Main.Main;
      End_Tasks;
   end Run;

end Mandelbrot_GUI;
