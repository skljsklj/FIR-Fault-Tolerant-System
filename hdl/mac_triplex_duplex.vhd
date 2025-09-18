library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.util_pkg.all;

entity mac_triplex_duplex is
    generic(
        fir_ord                         : natural := 5;      -- number of taps
        input_data_width                : natural := 24;
        -- number of pair-and-a-spare voter instances per TDR (e.g. 4 or 5)
        number_of_voters_for_one_tdr    : natural := 4;
        output_data_width               : natural := 48       -- default 2*input width
    );
    Port (
        clk_i       : in  std_logic;
        coef_addr_i : in  std_logic_vector(log2c(fir_ord)-1 downto 0);
        coef_i      : in  std_logic_vector(input_data_width-1 downto 0);
        data_i      : in  std_logic_vector(input_data_width-1 downto 0);
        data_o      : out std_logic_vector(output_data_width-1 downto 0)
    );
end mac_triplex_duplex;

architecture Behavioral of mac_triplex_duplex is
    type std_2d is array (0 to fir_ord*6-1) of std_logic_vector(2*input_data_width-1 downto 0);
    type std_2d_pairs is array (0 to fir_ord*3-1) of std_logic_vector(2*input_data_width-1 downto 0);
    -- voted outputs per stage (flattened across voters and stages)
    type voters_flat_t is array (0 to (number_of_voters_for_one_tdr*fir_ord)-1)
        of std_logic_vector(2*input_data_width-1 downto 0);
    -- generic unconstrained array for switch lines (data + error bit)
    type switch_line_t is array (natural range <>) of std_logic_vector(2*input_data_width downto 0);
    type error_bits_t is array (natural range <>) of std_logic;

    type coef_t is array (0 to fir_ord-1) of std_logic_vector(input_data_width-1 downto 0);
    signal b_s : coef_t := (others => (others => '0'));

    constant total_num_of_voters : natural := number_of_voters_for_one_tdr * fir_ord; -- total across all stages

    signal mac_out  : std_2d := (others => (others => '0'));
    signal pair_out : std_2d_pairs := (others => (others => '0'));

    signal data_o_pair  : voters_flat_t := (others => (others => '0'));
    signal data_o_spare : voters_flat_t := (others => (others => '0'));

    -- lines toward switch (data + 1 error bit)
    signal data_to_switch : switch_line_t(0 to total_num_of_voters-1) := (others => (others => '0'));

    -- two selected lines
    -- per-TDR selector signals (two channels) sized by number_of_voters_for_one_tdr
    type sel_arr is array (0 to fir_ord-1) of std_logic_vector(log2c(number_of_voters_for_one_tdr)-1 downto 0);
    signal sel_data_1 : sel_arr := (others => std_logic_vector(to_unsigned(0, log2c(number_of_voters_for_one_tdr))));
    signal sel_data_2 : sel_arr := (others => std_logic_vector(to_unsigned(1, log2c(number_of_voters_for_one_tdr))));

    -- per-TDR mux outputs and selected data
    type mux_word_arr is array (0 to fir_ord-1) of std_logic_vector(2*input_data_width downto 0);
    type stage_vec is array (0 to fir_ord-1) of std_logic_vector(2*input_data_width-1 downto 0);
    signal data_from_mux_1 : mux_word_arr := (others => (others => '0'));
    signal data_from_mux_2 : mux_word_arr := (others => (others => '0'));
    signal data_from_mux_s : stage_vec := (others => (others => '0'));

    signal error_bit : error_bits_t(0 to total_num_of_voters-1) := (others => '0');

    type errcmp_arr is array (0 to fir_ord-1) of std_logic;
    signal error_from_comparator : errcmp_arr := (others => '0');
    -- per-TDR counters sized by voters-per-TDR
    type cnt_arr is array (0 to fir_ord-1) of unsigned(log2c(number_of_voters_for_one_tdr)-1 downto 0);
    signal counter   : cnt_arr := (others => to_unsigned(2, log2c(number_of_voters_for_one_tdr)));
    constant max_index : unsigned (log2c(number_of_voters_for_one_tdr)-1 downto 0) :=
        to_unsigned(number_of_voters_for_one_tdr-1, log2c(number_of_voters_for_one_tdr));

    signal data_outt_s : std_logic_vector (2*input_data_width-1 downto 0) := (others => '0');
    signal stage_selected : stage_vec := (others => (others => '0'));

begin

    -- coefficient load: external write into coefficient register bank
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            b_s(to_integer(unsigned(coef_addr_i))) <= coef_i;
        end if;
    end process;

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
                         b_i=>b_s(0),
                         sec_i=>(others=>'0'),
                         sec_o=>mac_out(0+i));
            end generate mac_first;
    
            mac_others: if j /= 0 generate
                mac_instance:
                entity work.mac(behavioral)
                generic map(input_data_width=>input_data_width)
                port map(clk_i=>clk_i,
                         u_i=>data_i,
                         b_i=>b_s(j),
                         sec_i=>stage_selected(j-1), -- izlaz iz switch-a prethodnog TDR-a
                         sec_o=>mac_out(j*6+i));
            end generate mac_others;
    
        end generate triplex_instance;
    end generate;
    
    -- Duplex voting for each pair (0,1), (2,3), (4,5)
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            for j in 0 to fir_ord-1 loop
                if mac_out(j*6+0) = mac_out(j*6+1) then
                    pair_out(j*3+0) <= mac_out(j*6+0);
                else
                    pair_out(j*3+0) <= (others => '0');
                end if;

                if mac_out(j*6+2) = mac_out(j*6+3) then
                    pair_out(j*3+1) <= mac_out(j*6+2);
                else
                    pair_out(j*3+1) <= (others => '0');
                end if;

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
        begin
            -- bitwise majority of the three pair outputs; duplicated N times per stage (pair and spare voters)
            data_o_pair(j*number_of_voters_for_one_tdr + i)  <= (pair_out(j*3+0) and pair_out(j*3+1)) or
                                                                (pair_out(j*3+1) and pair_out(j*3+2)) or
                                                                (pair_out(j*3+2) and pair_out(j*3+0));

            data_o_spare(j*number_of_voters_for_one_tdr + i) <= (pair_out(j*3+0) and pair_out(j*3+1)) or
                                                                (pair_out(j*3+1) and pair_out(j*3+2)) or
                                                                (pair_out(j*3+2) and pair_out(j*3+0));

            if data_o_pair(j*number_of_voters_for_one_tdr + i) /= data_o_spare(j*number_of_voters_for_one_tdr + i) then
                error_bit(j*number_of_voters_for_one_tdr + i) <= '1';
            else
                error_bit(j*number_of_voters_for_one_tdr + i) <= '0';
            end if;

            -- bundle data and error for per-stage switch (LSB = error)
            data_to_switch(j*number_of_voters_for_one_tdr + i) <= data_o_pair(j*number_of_voters_for_one_tdr + i) &
                                                                  error_bit(j*number_of_voters_for_one_tdr + i);
        end generate;
    end generate;

    -- per-TDR multiplexers: select within the j-th stage voter set
    mux_per_stage:
    for j in 0 to fir_ord-1 generate
        data_from_mux_1(j) <= data_to_switch(j*number_of_voters_for_one_tdr +
                                             to_integer(unsigned(sel_data_1(j))));
        data_from_mux_2(j) <= data_to_switch(j*number_of_voters_for_one_tdr +
                                             to_integer(unsigned(sel_data_2(j))));
    end generate;

    --error detection from comparator 
    -- error detection per TDR
    err_detect:
    for j in 0 to fir_ord-1 generate
        process(clk_i)
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
    -- per-TDR counter/selector rotation
    rotate_select:
    for j in 0 to fir_ord-1 generate
        process(clk_i)
        begin
            if rising_edge(clk_i) then
                if (error_from_comparator(j) = '1' and data_from_mux_1(j)(0) = '1' and sel_data_1(j) /= std_logic_vector(counter(j))) then
                    sel_data_1(j) <= std_logic_vector(counter(j));
                    if counter(j) = max_index then
                        counter(j) <= (others => '0');
                    else
                        counter(j) <= counter(j) + 1;
                    end if;
                elsif (error_from_comparator(j) = '1' and data_from_mux_2(j)(0) = '1' and sel_data_2(j) /= std_logic_vector(counter(j))) then
                    sel_data_2(j) <= std_logic_vector(counter(j));
                    if counter(j) = max_index then
                        counter(j) <= (others => '0');
                    else
                        counter(j) <= counter(j) + 1;
                    end if;
                end if;
            end if;
        end process;
    end generate;

    -- choose non-erroneous path per stage
    choose_good:
    for j in 0 to fir_ord-1 generate
        process(clk_i)
        begin
            if rising_edge(clk_i) then
                if data_from_mux_1(j)(0) = '0' then
                    data_from_mux_s(j) <= data_from_mux_1(j)(2*input_data_width downto 1);
                elsif data_from_mux_2(j)(0) = '0' then
                    data_from_mux_s(j) <= data_from_mux_2(j)(2*input_data_width downto 1);
                else
                    data_from_mux_s(j) <= (others => '0');
                end if;
            end if;
        end process;
    end generate;
    
    -- register per-stage selected output for chaining
    stage_reg:
    for j in 0 to fir_ord-1 generate
        process(clk_i)
        begin
            if rising_edge(clk_i) then
                stage_selected(j) <= data_from_mux_s(j);
            end if;
        end process;
    end generate;

    -- final output is the last stage selected value
    data_outt_s <= stage_selected(fir_ord-1);
    data_o <= std_logic_vector(resize(signed(data_outt_s), output_data_width));

end Behavioral;
