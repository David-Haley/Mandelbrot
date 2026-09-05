--  Program to display mandelbrot set
--  Author    : David Haley
--  Created   : 05/09/2026
--  Last Edit : 05/09/2026

with Ada.Numerics.Generic_Complex_Types;
with Interfaces; use Interfaces;

procedure Mandelbrot is

type Real is digits 15;

package Complex_Numbers is new Ada.Numerics.Generic_Complex_Types (Real);
use Complex_Numbers;

subtype Colour_Insdices is Unsigned_8;
subtype Display_Indices is Natural range 0 .. 1023;

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

   Display_Buffer : Display_Buffers;

   Bottom_Left : Complex := (-2.0, -2.0);
   Top_Right : Complex := (2.0, 2.0);

begin -- Mandelbrot
   Generate_Set (Bottom_Left, Top_Right, Display_Buffer);
end Mandelbrot;