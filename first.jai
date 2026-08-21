#run build();

build :: ()
{
    // Auto: For release builds do this: jai first.jai -release
    // Remember to move ast folder to release folder 
    is_release := false;
    for arg : get_toplevel_command_line()
    {
        if arg == "-release" is_release = true;
    }

    {
        w := compiler_create_workspace();

        options := get_build_options();
        options.output_executable_name = "TetrisTower";

        if is_release
        {
            set_optimization(*options, .OPTIMIZED, preserve_debug_info = false);

            options.additional_linker_arguments = .["/SUBSYSTEM:WINDOWS", "/ENTRY:mainCRTStartup"];

            options.output_path = "build/release";
        }
        else
        {
            set_optimization(*options, .DEBUG);
        }

        set_build_options(options, w);

        add_build_file("./src/main.jai", w);
    }

    set_build_options_dc(.{do_output=false});
}

#import "Basic";
#import "Compiler";
