# Gemini Development Instructions

Please follow these guidelines when contributing to this repository:

## General Guidelines

- This project is a macOS application for switching wallpapers on the Mac using pictures from a Google Photos album
- The code should use the latest available Swift language and library versions
- Always consider multiple different aproaches, and choose the best one.
- Add code comments only for complex or unintuitive code
- Error messages must be concise but very precise
- Always first present the action plan to the user and only proceed with code changes after confirmation
- Write informative but concise git commit messages. If multi-line messages are impossible, write a detailed message while staying in a single line
- Before beginning to build anything dependent on an external API, make sure the endpoint is available, its permissions are still active, and what are its inputs and outputs.


## Tool Usage Guidelines

- **Always prioritize user instructions.**
- **For file modifications, prefer `write_file` over `replace`, as `replace` has been proven unreliable.**
- **Provide clear, concise explanations for any actions taken.**
- **Request user verification after significant changes.**
- **Test each set of changes using `xcodebuild -scheme GPhotoPaper build`.**