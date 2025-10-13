library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.util_pkg.all;

entity mac_triplex_duplex is
    generic(
        fir_ord                         : natural := 20;      
        input_data_width                : natural := 24;
        -- number of pair-and-a-spare voter instances per TDR (e.g. 4 or 5)
        number_of_voters_for_one_tdr    : natural := 5;
        output_data_width               : natural := 24       
    );
    Port (
        clk_i       : in  std_logic;
        coef_addr_i : in  std_logic_vector(log2c(fir_ord)-1 downto 0);
        coef_i      : in  std_logic_vector(input_data_width-1 downto 0);
        data_i      : in  std_logic_vector(input_data_width-1 downto 0);
        we_i        : in  std_logic; 
        data_o      : out std_logic_vector(output_data_width-1 downto 0)
    );
end mac_triplex_duplex;

architecture Behavioral of mac_triplex_duplex is
    attribute resource_sharing : string;
    attribute resource_sharing of Behavioral : architecture is "no";
    -- total number of MAC stages = fir_ord + 1
    constant num_stages : natural := fir_ord + 1;
    -- 6 replicas per stage
    type std_2d is array (0 to num_stages*6-1) of std_logic_vector(2*input_data_width-1 downto 0);
    -- 3 pairs per stage
    type std_2d_pairs is array (0 to num_stages*3-1) of std_logic_vector(2*input_data_width-1 downto 0);
    -- voted outputs per stage (flattened across voters and stages)
    type voters_flat_t is array (0 to (number_of_voters_for_one_tdr*num_stages)-1)
        of std_logic_vector(2*input_data_width-1 downto 0);
    -- generic unconstrained array for switch lines (data + error bit)
    type switch_line_t is array (natural range <>) of std_logic_vector(2*input_data_width downto 0);
    type error_bits_t is array (natural range <>) of std_logic;

    -- store fir_ord+1 coefficients; TB addresses 0..fir_ord
    type coef_t is array (0 to fir_ord) of std_logic_vector(input_data_width-1 downto 0);
    signal b_s : coef_t := (others => (others => '0'));

    constant total_num_of_voters : natural := number_of_voters_for_one_tdr * num_stages; -- total across all stages

    signal mac_out  : std_2d := (others => (others => '0'));
    signal pair_out : std_2d_pairs := (others => (others => '0'));

    signal data_o_pair  : voters_flat_t := (others => (others => '0'));
    signal data_o_spare : voters_flat_t := (others => (others => '0'));

    -- lines toward switch (data + 1 error bit)
    signal data_to_switch : switch_line_t(0 to total_num_of_voters-1) := (others => (others => '0'));
    signal data_to_switch1 : switch_line_t(0 to total_num_of_voters-1) := (others => (others => '0'));
    signal data_to_switch2 : switch_line_t(0 to total_num_of_voters-1) := (others => (others => '0'));
    
    -- two selected lines
    -- per-TDR selector signals (two channels) sized by number_of_voters_for_one_tdr
    type sel_arr is array (0 to num_stages-1) of std_logic_vector(log2c(number_of_voters_for_one_tdr)-1 downto 0);
    signal sel_data_1 : sel_arr := (others => std_logic_vector(to_unsigned(0, log2c(number_of_voters_for_one_tdr))));
    signal sel_data_2 : sel_arr := (others => std_logic_vector(to_unsigned(0, log2c(number_of_voters_for_one_tdr))));

    -- per-TDR mux outputs and selected data
    type mux_word_arr is array (0 to num_stages-1) of std_logic_vector(2*input_data_width downto 0);
    type stage_vec is array (0 to num_stages-1) of std_logic_vector(2*input_data_width-1 downto 0);
    signal data_from_mux_1 : mux_word_arr := (others => (others => '0'));
    signal data_from_mux_2 : mux_word_arr := (others => (others => '0'));
    signal data_from_mux_s : stage_vec := (others => (others => '0'));

    signal error_bit : error_bits_t(0 to total_num_of_voters-1) := (others => '0');

    type errcmp_arr is array (0 to num_stages-1) of std_logic;
    signal error_from_comparator : errcmp_arr := (others => '0');
    -- per-TDR counters sized by voters-per-TDR
    type cnt_arr is array (0 to num_stages-1) of unsigned(log2c(number_of_voters_for_one_tdr)-1 downto 0);
    signal counter   : cnt_arr := (others => to_unsigned(1, log2c(number_of_voters_for_one_tdr)));
    constant max_index : unsigned (log2c(number_of_voters_for_one_tdr)-1 downto 0) :=
        to_unsigned(number_of_voters_for_one_tdr-1, log2c(number_of_voters_for_one_tdr));

    signal data_outt_s : std_logic_vector (2*input_data_width-1 downto 0) := (others => '0');
    signal stage_selected : stage_vec := (others => (others => '0'));
    
    attribute dont_touch : string;   
    -- attribute dont_touch of pair_out : signal is "true"; 
    -- attribute dont_touch of data_o_pair : signal is "true";                  
    -- attribute dont_touch of data_o_spare : signal is "true"; 
    attribute dont_touch of data_to_switch1 : signal is "true";
    attribute dont_touch of data_to_switch2 : signal is "true";                              
    attribute dont_touch of sel_data_1 : signal is "true"; 
    attribute dont_touch of sel_data_2 : signal is "true";

begin

    -- coefficient load: external write into coefficient register bank
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if we_i = '1' then
                b_s(to_integer(unsigned(coef_addr_i))) <= coef_i;
            end if;            
        end if;
    end process;
    
    mac_first :
    for i in 0 to 5 generate
        mac_instance:
        entity work.mac(behavioral)
        generic map(input_data_width=>input_data_width)
        port map(clk_i=>clk_i,
                 u_i=>data_i,
                 -- first stage uses the last coefficient (reverse order)
                 b_i=>b_s(fir_ord),
                 sec_i=>(others=>'0'),
                 sec_o=>mac_out(0+i));
        end generate mac_first;

    -- Remaining stages 1..fir_ord (inclusive) to cover all taps
    others_section:
    for j in 1 to fir_ord generate
        triplex_instance:
        for i in 0 to 5 generate
            mac_others:
            entity work.mac(behavioral)
            generic map(input_data_width=>input_data_width)
            port map(clk_i=>clk_i,
                     u_i=>data_i,
                     -- subsequent stages use reversed coefficient index
                     b_i=>b_s(fir_ord - j),
                     sec_i=>stage_selected(j-1), -- izlaz iz switch-a prethodnog TDR-a
                     sec_o=>mac_out(j*6+i));
            end generate triplex_instance;
        end generate others_section;
    
    -- Duplex voting for each pair (0,1), (2,3), (4,5) - combinational
    pair_vote_per_stage:
    for j in 0 to num_stages-1 generate
        pair0:
        pair_out(j*3+0) <= mac_out(j*6+0) when mac_out(j*6+0) = mac_out(j*6+1) else (others => '0');
        pair1:
        pair_out(j*3+1) <= mac_out(j*6+2) when mac_out(j*6+2) = mac_out(j*6+3) else (others => '0');
        pair2:
        pair_out(j*3+2) <= mac_out(j*6+4) when mac_out(j*6+4) = mac_out(j*6+5) else (others => '0');
    end generate pair_vote_per_stage;
    
    voter_logic_per_tdr:
    for j in 0 to num_stages - 1 generate
        voter_logic:
        for i in 0 to number_of_voters_for_one_tdr-1 generate
            -- bitwise majority of the three pair outputs; duplicated N times per stage (pair and spare voters)
            data_o_pair(j*number_of_voters_for_one_tdr + i)  <= (pair_out(j*3+0) and pair_out(j*3+1)) or
                                                                (pair_out(j*3+1) and pair_out(j*3+2)) or
                                                                (pair_out(j*3+2) and pair_out(j*3+0));

            data_o_spare(j*number_of_voters_for_one_tdr + i) <= (pair_out(j*3+0) and pair_out(j*3+1)) or
                                                                (pair_out(j*3+1) and pair_out(j*3+2)) or
                                                                (pair_out(j*3+2) and pair_out(j*3+0));

            -- concurrent conditional assignment for error flag
            error_bit(j*number_of_voters_for_one_tdr + i) <= '1'
                when data_o_pair(j*number_of_voters_for_one_tdr + i) /=
                     data_o_spare(j*number_of_voters_for_one_tdr + i)
                else '0';

            -- bundle data and error for per-stage switch (LSB = error)
            data_to_switch(j*number_of_voters_for_one_tdr + i) <= data_o_pair(j*number_of_voters_for_one_tdr + i) &
                                                                  error_bit(j*number_of_voters_for_one_tdr + i);
        end generate voter_logic;
    end generate voter_logic_per_tdr;

    -- per-TDR multiplexers: select within the j-th stage voter set
    mux_per_stage:
    for j in 0 to num_stages-1 generate
        data_to_switch1(j*number_of_voters_for_one_tdr) <=  data_to_switch(j*number_of_voters_for_one_tdr);
        assigning_value_for_mux1: 
        for i in 1 to number_of_voters_for_one_tdr-2 generate
            data_to_switch1(j*number_of_voters_for_one_tdr+i) <=  data_to_switch(j*number_of_voters_for_one_tdr+i+1);
        end generate;
        
        assigning_value_for_mux2: 
        for i in 0 to number_of_voters_for_one_tdr-2 generate
            data_to_switch2(j*number_of_voters_for_one_tdr+i) <=  data_to_switch(j*number_of_voters_for_one_tdr+i+1);
        end generate;
    end generate;
    
    mux_per_stage2:
    for j in 0 to num_stages-1 generate
        data_from_mux_1(j) <= data_to_switch1(j*number_of_voters_for_one_tdr + to_integer(unsigned(sel_data_1(j))));
        data_from_mux_2(j) <= data_to_switch2(j*number_of_voters_for_one_tdr + to_integer(unsigned(sel_data_2(j))));
    end generate;
    
    --error detection from comparator per TDR
    err_detect:
    for j in 0 to num_stages-1 generate
        process(clk_i, data_from_mux_1, data_from_mux_2)
        begin
            if rising_edge(clk_i) then
                if data_from_mux_1(j)(2*input_data_width downto 1) /= data_from_mux_2(j)(2*input_data_width downto 1) then
                    error_from_comparator(j) <= '1';
                else
                    error_from_comparator(j) <= '0';
                end if;
            end if;
        end process;
    end generate;

    --counter logic for cell in mux 
    rotate_select:
    for j in 0 to num_stages-1 generate
        process(clk_i)
        begin
            if rising_edge(clk_i) then
                if ((error_from_comparator(j) = '1' and data_from_mux_1(j)(0) = '1') and sel_data_1(j) /= std_logic_vector(counter(j)) and counter(j) < max_index ) then
                    sel_data_1(j) <= std_logic_vector(counter(j));
                    counter(j) <= counter(j) + 1; 
                elsif ((error_from_comparator(j) = '1' and data_from_mux_2(j)(0) = '1') and (sel_data_2(j) /= std_logic_vector(counter(j))) and counter(j) < max_index) then
                    sel_data_2(j) <= std_logic_vector(counter(j));
                    counter(j) <= counter(j) + 1; 
                else
                    counter(j) <= counter(j);
                end if;
            end if;
        end process;
    end generate;

    -- choose non-erroneous path per stage - combinational
    choose_good:
    for j in 0 to num_stages-1 generate
        data_from_mux_s(j) <= data_from_mux_1(j)(2*input_data_width downto 1) when data_from_mux_1(j)(0) = '0' else
                               data_from_mux_2(j)(2*input_data_width downto 1) when data_from_mux_2(j)(0) = '0' else
                               (others => '0');
    end generate;
    
    -- combinational per-stage selected output for chaining into next MAC
    stage_sel_comb:
    for j in 0 to num_stages-1 generate
        stage_selected(j) <= data_from_mux_s(j);
    end generate;

    process(clk_i)
    begin
        if rising_edge(clk_i) then
            data_o <= stage_selected(fir_ord)(2*input_data_width-2 downto 2*input_data_width-output_data_width-1);
        end if;
    end process;

end Behavioral;
