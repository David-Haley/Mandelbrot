--  Performs the mandelbrot set calculations using multiple cores.

--  Author    : David Haley
--  Created   : 05/09/2026
--  Last Edit : 07/09/2026

with Ada.Numerics.Generic_Complex_Types;
with Interfaces; use Interfaces;

package Calculation_Engine is

   type Real is digits 15;

   package Complex_Numbers is new Ada.Numerics.Generic_Complex_Types (Real);
   use Complex_Numbers;

   subtype Colour_Indices is Unsigned_8 range 0 .. 64;
   subtype Display_Indices is Natural range 0 .. 1023;

   type Display_Buffers is array (Display_Indices, Display_Indices) of
     Colour_Indices;

   Display_Buffer : Display_Buffers :=
     [others =>[others => Colour_Indices'First]];
   --  Must not be accessed during call to Generate_Set

   procedure Generate_Set (Bottom_Left, Top_Right : in Complex)
     with Pre => Top_Right.Re > Bottom_Left.Re and
                 Top_Right.Im > Bottom_Left.Im and
                 (Top_Right.Re - Bottom_Left.Re) =
                 (Top_Right.Im - Bottom_Left.Im);

   --  Performes calculations using multiple cores.

   procedure End_Tasks;

   -- Causes the calculation tasks to terminate.
   
private

   Cores : constant Positive := 4; -- must be 2**n
   subtype Calculator_Indices is Natural range 0 .. Cores - 1;
   
end Calculation_Engine;