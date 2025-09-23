library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use work.txt_util.all;
use work.util_pkg.all;

entity tb is
    generic(in_out_data_width : natural := 24;
            fir_ord : natural := 20);
--  Port ( );
end tb;

architecture Behavioral of tb is
    constant period : time := 20 ns;
    signal clk_i_s : std_logic;
    -- Use paths relative to the simulator run directory.
    -- Vivado xsim runs in vivado_project/fir_fault_tolerant_system.sim/sim_1/behav/xsim,
    -- from where HDL sources are referenced as ../../../../../hdl/...
    file input_test_vector    : text open read_mode is "../../../../../hdl/input.txt";
    file output_check_vector  : text open read_mode is "../../../../../hdl/expected.txt";
    file input_coef           : text open read_mode is "../../../../../hdl/coef.txt";
    signal data_i_s : std_logic_vector(in_out_data_width-1 downto 0);
    signal data_o_s : std_logic_vector(in_out_data_width-1 downto 0);
    signal coef_addr_i_s : std_logic_vector(log2c(fir_ord)-1 downto 0);
    signal coef_i_s : std_logic_vector(in_out_data_width-1 downto 0);
    signal we_i_s : std_logic;
    signal tmp : std_logic_vector(in_out_data_width-1 downto 0);
    
    signal start_check : std_logic := '0';

begin

    mac_triplex_duplex:
    entity work.mac_triplex_duplex(behavioral)
    generic map(fir_ord=>fir_ord,
                input_data_width=>in_out_data_width,
                output_data_width=>in_out_data_width)
    port map(clk_i=>clk_i_s,
             we_i=>we_i_s,
             coef_i=>coef_i_s,
             coef_addr_i=>coef_addr_i_s,
             data_i=>data_i_s,
             data_o=>data_o_s);

    clk_process:
    process
    begin
        clk_i_s <= '0';
        wait for period/2;
        clk_i_s <= '1';
        wait for period/2;
    end process;
    
    stim_process:
    process
        variable tv : line;
    begin
        --upis koeficijenata
        data_i_s <= (others=>'0');
        wait until falling_edge(clk_i_s);
        for i in 0 to fir_ord loop
            we_i_s <= '1';
            coef_addr_i_s <= std_logic_vector(to_unsigned(i,log2c(fir_ord)));
            readline(input_coef,tv);
            coef_i_s <= to_std_logic_vector(string(tv));
            wait until falling_edge(clk_i_s);
        end loop;
        --ulaz za filtriranje
        while not endfile(input_test_vector) loop
            readline(input_test_vector,tv);
            data_i_s <= to_std_logic_vector(string(tv));
            wait until falling_edge(clk_i_s);
            start_check <= '1';
        end loop;
        start_check <= '0';
        report "verification done!" severity failure;
    end process;
    
    check_process:
    process
        variable check_v : line;
        -- FIFO za poravnavanje ocekivanog izlaza sa latencijom cevi
        -- procena detaljnije: 2 ciklusa do stage_selected(0) (pair_out + choose_good + stage_reg = 3, ali mac_out koristi reg_s od prethodnog takta),
        -- pa +3 ciklusa po narednom TDR-u => ukupno 2 + 3*fir_ord
        constant PIPELINE_DELAY : natural := 2 + 3*fir_ord;
        type fifo_t is array (0 to PIPELINE_DELAY-1) of std_logic_vector(in_out_data_width-1 downto 0);
        variable q : fifo_t := (others => (others => '0'));
        variable wr : natural := 0;         -- pozicija za upis (i najstariji element za poredjenje pre upisa)
        variable filled : natural := 0;     -- broj popunjenih mesta
        variable exp_sample : std_logic_vector(in_out_data_width-1 downto 0);
    begin
        wait until start_check = '1';
        while(true)loop
            wait until rising_edge(clk_i_s);

            -- prvo (ako je FIFO pun) uporedi NAJSTARIJI element koji ce biti prepisan
            -- Prikazi u talasima koji uzorak bi se poredio (najstariji u FIFO)
            if filled > 0 then
                tmp <= q(wr);
            else
                tmp <= (others => '0');
            end if;

            -- Poredi tek kada je FIFO potpuno popunjen (validno poravnanje)
            if filled = PIPELINE_DELAY then
                if(abs(signed(q(wr)) - signed(data_o_s)) > "000000000000000000000111")then
                     report "result mismatch!" severity failure;
                end if;
            end if;

            -- procitaj sledece ocekivanje i upisi u FIFO
            if not endfile(output_check_vector) then
                readline(output_check_vector,check_v);
                exp_sample := to_std_logic_vector(string(check_v));
            else
                exp_sample := (others => '0');
            end if;
            -- za waveform prikaz (neporavnat, ali nije nula)
            tmp <= exp_sample;
            q(wr) := exp_sample;

            if filled < PIPELINE_DELAY then
                filled := filled + 1;
            end if;
            wr := (wr + 1) mod PIPELINE_DELAY;
        end loop;
    end process;
    
end Behavioral;
