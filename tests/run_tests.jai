#run build();

build :: ()
{
    w := compiler_create_workspace();

    options := get_build_options();
    options.output_executable_name = "TetrisTowerTests";

    set_build_options(options, w);

    add_build_file("./test_main.jai", w);

    set_build_options_dc(.{do_output=false});
}

#import "Basic";
#import "Compiler";
