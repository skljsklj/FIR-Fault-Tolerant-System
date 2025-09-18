library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.util_pkg.all;

entity mac_triplex_duplex is
    generic(fir_ord : natural := 5;
            input_data_width : natural := 24;
            number_of_voters_for_one_tdr : natural := 4;
            number_of_data_lines : natural := 4;
            number_of_errors : natural := 4;
            output_data_width : natural := 24);
    Port ( clk_i : in std_logic;
           coef_addr_i : std_logic_vector(log2c(fir_ord+1)-1 downto 0);
           coef_i : in std_logic_vector (input_data_width-1 downto 0);
           data_i : in std_logic_vector (input_data_width-1 downto 0);
           data_o : in std_logic_vector (output_data_width-1 downto 0)                                                            );
end mac_triplex_duplex;

architecture Behavioral of mac_triplex_duplex is
    type std_2d is array (fir_ord*6-1 downto 0) of std_logic_vector(2*input_data_width-1 downto 0);
    type total_number_of_voters is array (number_of_voters_for_one_tdr*fir_ord-1 downto 0) of std_logic_vector(2*input_data_width-1 downto 0);
    type data_switch_lines is array (number_of_data_lines-1 downto 0) of std_logic_vector(2*input_data_width downto 0);
    type error_bits is array (number_of_errors downto 0) of std_logic;
    signal mac_inter : std_2d:=(others=>(others=>'0'));
    type coef_t is array (fir_ord downto 0) of std_logic_vector(input_data_width-1 downto 0);
    signal b_s : coef_t := (others=>(others=>'0')); 

    type mux_line is array (0 to number_of_voters_for_one_tdr-1) of std_logic_vector(2*input_data_width-1 downto 0);

    -- signal data_to_mux  : mux_line:=(others=>(others=>'0'));
    signal data_to_switch : mux_line := (others=>(others=>'0')); 
    signal data_to_mux_1  : mux_line :=(others=>(others=>'0'));
    signal data_to_mux_2  : mux_line :=(others=>(others=>'0'));

    signal data_from_mux_1 : std_logic_vector (2*input_data_width-1 downto 0) := (others=>'0') ;
    signal data_from_mux_2 : std_logic_vector (2*input_data_width-1 downto 0) := (others=>'0') ;

    signal data_from_mux_s : std_logic_vector (2*input_data_width-1 downto 0) := (others => '0');
    
    constant total_num_of_voters : natural := number_of_voters_for_one_tdr * fir_ord;
    constant total_num_of_mux_one_tdr : natural := log2c(number_of_voters_for_one_tdr);
    
    signal mac_out : std_2d:= (others=>(others=>'0')); 
    signal pair_out : std_2d:= (others=>(others=>'0')); 
    signal data_o_pair : total_number_of_voters := (others=>(others=>'0'));
    signal data_o_spare : total_number_of_voters := (others=>(others=>'0'));

    signal sel_data_1 : std_logic_vector (log2c(number_of_voters_for_one_tdr)-1 downto 0) := std_logic_vector(to_unsigned(0, log2c(number_of_voters_for_one_tdr)));
    signal sel_data_2 : std_logic_vector (log2c(number_of_voters_for_one_tdr)-1 downto 0) := std_logic_vector(to_unsigned(0, log2c(number_of_voters_for_one_tdr)));
    
    
    signal error_bit : error_bits := (others=>'0'); 

    signal error_from_comparator : std_logic := '0';
    signal counter : unsigned (log2c(number_of_voters_for_one_tdr) - 1 downto 0) := (to_unsigned(1, log2c(number_of_voters_for_one_tdr)));
    signal checker : unsigned (log2c(number_of_voters_for_one_tdr) - 1 downto 0) := (to_unsigned(number_of_voters_for_one_tdr, log2c(number_of_voters_for_one_tdr)));
    signal data_outt_s : std_logic_vector (2*input_data_width - 2 downto 0) := (others => '0');  

begin

    triplex_gen:
    for j in 0 to fir_ord-1 generate
        triplex_instance:
        for i in 0 to 5 generate
            mac_first: if j = 0 generate
                mac_instance:
                entity work.mac(behavioral)
                generic map(input_data_width=>input_data_width)
                port map(clk_i=>clk_i,
                         u_i=>data_i,
                         b_i=>b_s(fir_ord),
                         sec_i=>(others=>'0'),
                         sec_o=>mac_out(0+i));
            end generate mac_first;
    
            mac_others: if j /= 0 generate
                mac_instance:
                entity work.mac(behavioral)
                generic map(input_data_width=>input_data_width)
                port map(clk_i=>clk_i,
                         u_i=>data_i,
                         b_i=>b_s(fir_ord-j),
                         sec_i=>mac_out((j-1)*6+i), --ulaz sec_i je izlaz iz switch-a
                         sec_o=>mac_out(j*6+i));
            end generate mac_others;
    
        end generate triplex_instance;
    end generate;
    
    -- Duplex voting za svaki par 
    process(clk_i, mac_out)
    begin
    if rising_edge(clk_i) then
        for j in 0 to fir_ord-1 loop
            -- par (0,1)
            if mac_out(j*6+0) = mac_out(j*6+1) then
                pair_out(j*3+0) <= mac_out(j*6+0);
            else
                pair_out(j*3+0) <= (others => '0');
            end if;
 
            -- par (2,3)
            if mac_out(j*6+2) = mac_out(j*6+3) then
                pair_out(j*3+1) <= mac_out(j*6+2);
            else
                pair_out(j*3+1) <= (others => '0');
            end if;
 
            -- par (4,5)
            if mac_out(j*6+4) = mac_out(j*6+5) then
                pair_out(j*3+2) <= mac_out(j*6+4);
            else
                pair_out(j*3+2) <= (others => '0');
            end if;
        end loop;
     end if;
    end process;
    
    voter_logic_per_tdr:
    for j in 0 to fir_ord - 1 generate
        voter_logic:
        for i in 0 to number_of_voters_for_one_tdr-1 generate
        process(pair_out)
        begin
            data_o_pair(i) <= (pair_out(i*3) and pair_out(i*3+1)) or
                            (pair_out(i*3+1) and pair_out(i*3+2)) or
                            (pair_out(i*3+2) and pair_out(i*3));

            data_o_spare(i) <= (pair_out(i*3) and pair_out(i*3+1)) or
                            (pair_out(i*3+1) and pair_out(i*3+2)) or
                            (pair_out(i*3+2) and pair_out(i*3));

            if data_o_pair(i) /= data_o_spare(i) then
                error_bit(i) <= '1';
            else
                error_bit(i) <= '0';
            end if;

                data_to_switch(i) <= data_o_pair(i) & error_bit(i);
            end process;
        end generate;
    end generate;

    data_to_mux_1(0) <=  data_to_switch(0);
    assigning_value_for_mux1: 
    for i in 1 to number_of_voters_for_one_tdr-2 generate
        data_to_mux_1(i) <=  data_to_switch(i+1);
    end generate;

    assigning_value_for_mux2: 
    for i in 0 to number_of_voters_for_one_tdr-2 generate
        data_to_mux_2(i) <=  data_to_switch(i+1);
    end generate;
  
    data_from_mux_1 <= data_to_mux_1(to_integer(unsigned(sel_data_1(log2c(number_of_voters_for_one_tdr)-1 downto 0))));
    data_from_mux_2 <= data_to_mux_2(to_integer(unsigned(sel_data_2(log2c(number_of_voters_for_one_tdr)-1 downto 0))));

    --error detection from comparator 
    process(clk_i,data_from_mux_1(2*input_data_width-1 downto 1),data_from_mux_2(2*input_data_width-1 downto 1)) 
    begin
        if(rising_edge(clk_i)) then
            if(data_from_mux_1(2*input_data_width-1 downto 1) /= data_from_mux_2(2*input_data_width-1 downto 1)) then
                error_from_comparator <= '1';
            else
                error_from_comparator <= '0';
            end if; 
        end if;
    end process;

    --counter logic for cell in mux 
    process(clk_i,error_from_comparator, data_from_mux_1(0),data_from_mux_2(0),sel_data_1,sel_data_2,counter)
    begin
        if(rising_edge(clk_i)) then
            if((error_from_comparator = '1' and data_from_mux_1(0) = '1') and sel_data_1 /= std_logic_vector(counter) and counter < checker) then  
                sel_data_1 <= std_logic_vector(counter);
                counter <= counter + 1;
            elsif((error_from_comparator = '1' and data_from_mux_2(0) = '1') and sel_data_2 /= std_logic_vector(counter) and counter < checker) then  
                sel_data_2 <= std_logic_vector(counter); 
                counter <= counter + 1;    
            else
                counter <= counter;
            end if;
        end if;                   
    end process;    

    -- 
    process(clk_i, data_from_mux_1,data_from_mux_2)
    begin
        if(rising_edge(clk_i)) then
            if(data_from_mux_1(0) = '0') then
                data_from_mux_s  <= data_from_mux_1(output_data_width-1 downto 1);    
            else
                data_from_mux_s  <= data_from_mux_2(output_data_width-1 downto 1);     
            end if;
        end if; 
    end process;
    
    process(clk_i,counter,checker,data_from_mux_1(output_data_width-1 downto 1)) 
    begin
        if(rising_edge(clk_i)) then
            if(counter = checker) then
                data_outt_s <= (others => '0'); 
            else
                data_outt_s <= data_from_mux_s; 
            end if;
        end if;
    end process; 

    -- mac_out <= data_outt_s;

   
end Behavioral;
