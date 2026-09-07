--  Performs the mandelbrot set calculations using multiple cores.

--  Author    : David Haley
--  Created   : 05/09/2026
--  Last Edit : 07/09/2026

package body Calculation_Engine is

   task type Calculators is
      entry Start (Y0 : in Calculator_Indices;
                   Bottom_Left_In : in Complex;
                   M_In : in Real);
      entry Idle;
      entry Stop;
   end Calculators;

   Calculator : array (Calculator_Indices) of Calculators;


   procedure Generate_Set (Bottom_Left, Top_Right : in Complex) is

      --  That is Bottom_Left and Top_Right define the corners of a square.

      M : constant Real := (Top_Right.Re - Bottom_Left.Re) /
        Real (Display_Indices'Last);

   begin -- Generate_Set
      for T in Calculator_Indices loop
         Calculator (T).Start (T, Bottom_Left, M);
      end loop; -- T in Calculator_Indices loop
      --  Don't return until all calculations are complete
      for T in Calculator_Indices loop
         Calculator (T).Idle;
      end loop; -- T in Calculator_Indices loop
   end Generate_Set;

   procedure End_Tasks is

      -- Causes the calculation tasks to terminate.

   begin -- End_Tasks
      for T in Calculator_Indices loop
         Calculator (T).Stop;
      end loop; -- T in Calculator_Indices
   end End_Tasks;

   task body Calculators is
   
      function C_Value (Bottom_Left : in Complex;
                        M : in Real;
                        X, Y : in Display_Indices) return Complex
        with Inline => True is

      begin -- C_Value
         return Bottom_Left + (M * Real (X), M * Real (Y));
      end C_Value;

      function Diverge (C : in Complex) return Colour_Indices
        with inline => True is

         Z : Complex := (0.0, 0.0);
         Limit : constant Real := 2.0;
         Result : Colour_Indices := Colour_Indices'First;

      begin -- Diverge
         if Modulus (C) >= Limit then
            return Result;
         end if; -- Modulus (C) >= Limit
         while Modulus (Z) < Limit and Result < Colour_Indices'Last loop
            Z := Z ** 2 + C;
            Result := @ + 1;
         end loop; -- Modulus (Z) < Limit and Result < Colour_Indices'Last
         return Result;
      end Diverge;

      Run : Boolean := True;
      Bottom_Left : Complex;
      M : Real;
      Y : Display_Indices;
      Finished : Boolean := True;

   begin -- Calculators
      while Run loop
         select
            accept Start (Y0 : in Calculator_Indices;
                          Bottom_Left_In : in Complex;
                          M_In : in Real) do

               Bottom_Left := Bottom_Left_In;
               M := M_In;
               Y := Y0;
               Finished := False;
            end Start;
         or
            when Finished  => accept Idle;
         or
            accept Stop do
               Run := False;
            end Stop;
         else
            while not Finished loop
               for X in Display_Indices loop
                  Display_Buffer (X, Y) := Diverge (C_Value (Bottom_Left,
                                                             M,
                                                             X,
                                                             Y));
               end loop; -- X in Display_Indices
               if Y + Cores < Display_Indices'Last then
                  Y := @ + Cores;
               else
                  Finished := True;
               end if; -- Y + Cores < Display_Indices'Last
            end loop; -- not Finished
            delay 0.01;
            --  Compromise between making start of calculations responsive
            --  and wasting CPU time
         end select;
      end loop; -- Run
   end Calculators; 

end Calculation_Engine;