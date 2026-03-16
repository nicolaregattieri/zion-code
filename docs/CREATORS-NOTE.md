# Creator's Note

I created Zion because I really enjoy coding using terminals -- split terminals, different tabs, multiple LLMs running at the same time. I believe every LLM has its own place and its own strengths.

What I missed from existing code editors and Git clients was control. The ability to see what each LLM is doing, organize outcomes across branches, review the commits they create, and manage workspaces -- all with full visibility.

So I built a Git client first. And I was really happy with the results. Then I thought: I should be able to see everything and do everything inside one application.

Today, with growing concerns about memory and resource usage, we know that Electron and web-based tools consume a lot of RAM. So I built Zion to be lightweight, native Swift, fully compatible with Apple devices -- less resource-demanding by design.

The editor is intentionally simple and lightweight. It's there to help you inspect and review what AI builds, not to replace a full IDE with dozens of plugins. The terminal is where development happens now, and I think that experience will only keep evolving.

As a frontend developer, I also needed something that avoids the constant back-and-forth between applications. Losing focus during a coding session is expensive. So I created the Smart Clipboard -- capture screenshots, errors, logs, and drag them straight into any terminal without ever leaving Zion.

I created Zion to help me code faster without losing focus. To control everything, see everything, and manage everything in one single place.

Zion is the view from the top.

-- Nicola Regattieri
