# Gemini Development Instructions

Please follow these guidelines when contributing to this repository:

## General Guidelines

- This project is a macOS application for switching wallpapers on the Mac using pictures from a Google Photos album
- The code should use the latest available Swift language and library versions
- Add code comments only for complex or unintuitive code
- Error messages must be concise but very precise
- Always first present the action plan to the user and only proceed with code changes after confirmation
- Include the prompt used to generate the code in the commit message



## Tool Usage Guidelines

- **Always prioritize user instructions.**
- **For file modifications, prefer `write_file` over `replace`, as `replace` has been proven unreliable.**
- **Provide clear, concise explanations for any actions taken.**
- **Request user verification after significant changes.**
- **Test each set of changes using `xcodebuild -scheme GPhotoPaper build`.**