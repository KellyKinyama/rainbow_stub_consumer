import 'package:rearch/rearch.dart';

/// Global writable slot holding the thread key of the currently
/// visible chat page, or null when the user is elsewhere. Read by
/// notification code that wants to suppress toasts when the target
/// chat is already on screen.
ValueWrapper<String?> activeThreadCapsule(CapsuleHandle use) =>
    use.data<String?>(null);
