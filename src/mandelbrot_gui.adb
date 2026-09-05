--  GtkAda user interface for displaying the Mandelbrot Display_Buffer.
--  Author    : David Haley
--  Created   : 05/09/2026
--  Last Edit : 05/09/2026

with Ada.Numerics.Generic_Complex_Types;
with Interfaces; use Interfaces;

with Glib; use Glib;
with Gtk.Window; use Gtk.Window;
with Gtk.Widget; use Gtk.Widget;
with Gtk.Drawing_Area; use Gtk.Drawing_Area;
with Gtk.Enums; use Gtk.Enums;
with Gtk.Main;
with Cairo; use Cairo;
with Cairo.Image_Surface; use Cairo.Image_Surface;

package body Mandelbrot_GUI is

type Real is digits 15;

package Complex_Numbers is new Ada.Numerics.Generic_Complex_Types (Real);
use Complex_Numbers;

subtype Colour_Insdices is Unsigned_8;
subtype Display_Indices is Natural range 0 .. 1023;

Image_Size : constant := Display_Indices'Last - Display_Indices'First + 1;

type Display_Buffers is array (Display_Indices, Display_Indices) of
  Colour_Insdices;

   procedure Generate_Set (Bottom_Left, Top_Right : in Complex;
                           Display_Buffer : out Display_Buffers)
     with Pre => Top_Right.Re > Bottom_Left.Re and
                 Top_Right.Im > Bottom_Left.Im and
                 (Top_Right.Re - Bottom_Left.Re) =
                 (Top_Right.Im - Bottom_Left.Im) is

      --  That is Bottom_Left and Top_Right define the corners of a square.

      M : constant Real := (Top_Right.Re - Bottom_Left.Re) /
        Real (Display_Indices'Last);
      C : Complex;

      function Diverge (C_In : in Complex) return Colour_Insdices is

         C : Complex := C_In;
         Limit : constant Real := 2.0;
         Result : Colour_Insdices := Colour_Insdices'First;

      begin -- Diverge
         while Modulus (C) < Limit and Result < Colour_Insdices'Last loop
            C := C ** 2 + C;
            Result := @ + 1;
         end loop; -- Modulus (C) < Limit and Result < Colour_Insdices'Last
         return Result;
      end Diverge;

   begin -- Generate_Set
      for X in Display_Indices loop
         for Y in Display_Indices loop
            C := Bottom_Left + (M * Real (X), M * Real (Y));
            Display_Buffer (X, Y) := Diverge (C);
         end loop; -- Y in Display_Indices
      end loop; -- X in Display_Indices
   end Generate_Set;

   --  Colour_Indices 0 .. 254 are mapped to vivid, fully saturated colours
   --  around the hue wheel; 255 (the point never diverged) is displayed as
   --  black.

   type Palette_Arrays is array (Colour_Insdices) of RGB24_Data;

   function Build_Palette return Palette_Arrays is

      Palette : Palette_Arrays;

      function Hue_To_RGB (Index : Colour_Insdices) return RGB24_Data is

         Hue : constant Float := 360.0 * Float (Index) / 255.0;
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
      for I in Colour_Insdices loop
         if I = Colour_Insdices'Last then
            Palette (I) := (Red => 0, Green => 0, Blue => 0);
         else
            Palette (I) := Hue_To_RGB (I);
         end if;
      end loop; -- I in Colour_Insdices
      return Palette;
   end Build_Palette;

   Surface : Cairo_Surface;

   function On_Draw (Self : access Gtk_Widget_Record'Class;
                      Cr   : Cairo.Cairo_Context) return Boolean is

      pragma Unreferenced (Self);

   begin -- On_Draw
      Set_Source_Surface (Cr, Surface, 0.0, 0.0);
      Paint (Cr);
      return False;
   end On_Draw;

   procedure On_Destroy (Self : access Gtk_Widget_Record'Class) is

      pragma Unreferenced (Self);

   begin -- On_Destroy
      Gtk.Main.Main_Quit;
   end On_Destroy;

   procedure Run is

      Display_Buffer : Display_Buffers;
      Palette : constant Palette_Arrays := Build_Palette;

      Bottom_Left : constant Complex := (-2.0, -2.0);
      Top_Right : constant Complex := (2.0, 2.0);

      Pixel_Data : constant RGB24_Array_Access :=
        new RGB24_Array (0 .. Image_Size * Image_Size - 1);

      Window : Gtk_Window;
      Drawing_Area : Gtk_Drawing_Area;

   begin -- Run
      Generate_Set (Bottom_Left, Top_Right, Display_Buffer);
      for X in Display_Indices loop
         for Y in Display_Indices loop
            Pixel_Data (Y * Image_Size + X) :=
              Palette (Display_Buffer (X, Y));
         end loop; -- Y in Display_Indices
      end loop; -- X in Display_Indices
      Surface := Create_For_Data_RGB24 (Pixel_Data, Gint (Image_Size),
                                         Gint (Image_Size));

      Gtk.Main.Init;

      Gtk_New (Window, Window_Toplevel);
      Window.Set_Title ("Mandelbrot");
      Window.Set_Resizable (False);

      Gtk_New (Drawing_Area);
      Drawing_Area.Set_Size_Request (Gint (Image_Size), Gint (Image_Size));
      Drawing_Area.On_Draw (On_Draw'Access);

      Window.Add (Drawing_Area);
      Window.On_Destroy (On_Destroy'Access);

      Window.Show_All;
      Gtk.Main.Main;
   end Run;

end Mandelbrot_GUI;
