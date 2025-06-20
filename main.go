package main

import (
  "bytes"
  "flag"
  "fmt"
  "os"
  "io"
  "os/exec"
  "path/filepath"
  "strings"
  "time"

  "github.com/briandowns/spinner"
)

func script(file string) string {
    return filepath.Join("assets/scripts", file)
}

func main() {
    // 参数解析
    step := flag.String("step", "", "只执行指定步骤，空则全量执行")
    domain := flag.String("domain", "", "域名，例如 example.com")
    hostname := flag.String("hostname", "", "SMTP 主机名，例如 smtp.example.com")
    smtpUser := flag.String("smtp-user", "", "SMTP 用户名")
    smtpPass := flag.String("smtp-pass", "", "SMTP 密码")
    selector := flag.String("selector", "", "DKIM 选择器，可选，不填自动生成")
    flag.Parse()

    if *domain == "" || *hostname == "" || *smtpUser == "" || *smtpPass == "" {
        fmt.Fprintln(os.Stderr, "用法: --domain X --hostname Y --smtp-user U --smtp-pass P [--step name]")
        os.Exit(1)
    }

    run := func(name string, fn func() error) {
        if *step == "" || *step == name {
            s := spinner.New(spinner.CharSets[14], 100*time.Millisecond)
            s.Color("green")
            s.Prefix = fmt.Sprintf("→ %s... ", name)
            s.Start()
            err := fn()
            s.Stop()
            if err != nil {
                fmt.Fprintf(os.Stderr, "\r✗ %s 失败: %v\n", name, err)
                os.Exit(1)
            }
            fmt.Printf("\r✔ %s 完成\n", name)
            if *step == name {
                os.Exit(0)
            }
        }
    }

    run("install_deps", func() error {
        cmd := exec.Command("bash", script("01-system_update.sh"))
        cmd.Env = os.Environ()
        cmd.Stdout = os.Stdout
        cmd.Stderr = os.Stderr
        return cmd.Run()
    })

    cfToken := os.Getenv("CF_API_TOKEN")
    if *domain == "" || *hostname == "" || *smtpUser == "" || *smtpPass == "" {
        fmt.Fprintln(os.Stderr, "用法: --domain X --hostname Y --smtp-user U --smtp-pass P [--step name]")
        os.Exit(1)
    }

    run("install_deps", func() error {
        cmd := exec.Command("bash", script("01-system_update.sh"))
        cmd.Env = os.Environ()
        cmd.Stdout = os.Stdout
        cmd.Stderr = os.Stderr
        return cmd.Run()
    })

    run("gen_dkim", func() error {
        cmd := exec.Command("bash", script("03-gen_dkim.sh"))
        // 强制清空 SELECTOR，保证脚本每次都重新生成
        env := []string{}
        for _, e := range os.Environ() {
            if strings.HasPrefix(e, "SELECTOR=") {
                continue
            }
            env = append(env, e)
        }
        // 确保脚本里 SELECTOR 变量为空
        env = append(env, "SELECTOR=")
        cmd.Env = env
        cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
        return cmd.Run()
    })

    run("write_assets", func() error {
        const (
            srcPath    = "assets/PowerMTA-5.0r8.deb"
            destFolder = "/tmp/assets/assets"
            destPath   = destFolder + "/PowerMTA-5.0r8.deb"
            minSize    = 100 << 20 // 100 MiB
            maxTries   = 3
        )
        if err := os.MkdirAll(destFolder, 0755); err != nil {
            return fmt.Errorf("创建目录 %s 失败: %w", destFolder, err)
        }
        for i := 1; i <= maxTries; i++ {
            in, err := os.Open(srcPath)
            if err != nil {
                return fmt.Errorf("第 %d 次：打开源安装包 %s 失败: %w", i, srcPath, err)
            }
            out, err := os.Create(destPath)
            if err != nil {
                in.Close()
                return fmt.Errorf("第 %d 次：创建目标文件 %s 失败: %w", i, destPath, err)
            }
            if _, err := io.Copy(out, in); err != nil {
                in.Close()
                out.Close()
                return fmt.Errorf("第 %d 次：拷贝安装包失败: %w", i, err)
            }
            if err := out.Sync(); err != nil {
                in.Close()
                out.Close()
                return fmt.Errorf("第 %d 次：同步到磁盘失败: %w", i, err)
            }
            in.Close()
            out.Close()
            fi, err := os.Stat(destPath)
            if err != nil {
                return fmt.Errorf("第 %d 次：读取文件信息失败: %w", i, err)
            }
            if fi.Size() >= minSize {
                return nil
            }
            fmt.Fprintf(os.Stderr, "第 %d 次：目标文件大小 %d 字节，小于 %d，重试中…\n", i, fi.Size(), minSize)
            time.Sleep(2 * time.Second)
        }
        return fmt.Errorf("多次尝试后，%s 仍小于 %d 字节，拷贝可能不完整", destPath, minSize)
    })

    run("get_public_ip", func() error {
        return exec.Command("bash", script("04-get_public_ip.sh")).Run()
    })

    run("fetch_zone", func() error {
        cmd := exec.Command("bash", script("05-fetch_zone.sh"))
        cmd.Env = append(os.Environ(),
            "CF_API_TOKEN="+cfToken,
            "DOMAIN="+*domain,
        )
        cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
        return cmd.Run()
    })

    run("update_dns", func() error {
        cmd := exec.Command("bash", script("06-update_dns.sh"))
        cmd.Env = append(os.Environ(),
            "CF_API_TOKEN="+cfToken,
            "DOMAIN="+*domain,
            "HOSTNAME="+*hostname,
            "ZONE_ID="+readSecret("/tmp/pmta-secrets/zone/zone_id.txt"),
            "SELECTOR="+readSecret("/tmp/pmta-secrets/dkim/selector.txt"),
            "PUBLIC_IP="+readSecret("/tmp/pmta-secrets/ip/public_ip.txt"),
        )
        cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
        return cmd.Run()
    })

    run("wait_dns", func() error {
        cmd := exec.Command("bash", script("06-wait_dns.sh"))
        cmd.Env = append(os.Environ(),
            "DOMAIN="+*domain,
            "HOSTNAME="+*hostname,
            "SELECTOR="+readSecret("/tmp/pmta-secrets/dkim/selector.txt"),
            "PUBLIC_IP="+readSecret("/tmp/pmta-secrets/ip/public_ip.txt"),
        )
        cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
        return cmd.Run()
    })

run("install_acme", func() error {
    cmd := exec.Command("bash", script("07-install_acme.sh"))
    cmd.Env = append(os.Environ(),
        "DOMAIN="+*domain,
        "HOSTNAME="+*hostname,
        "ACME_EMAIL=abuse@"+*domain,
        "CF_API_TOKEN="+cfToken,
    )
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    return cmd.Run()
})

    run("install_pmta", func() error {
        return exec.Command("bash", script("08-install_pmta.sh")).Run()
    })

    run("write_configs", func() error {
        sel := *selector
        if sel == "" {
            sel = readSecret("/tmp/pmta-secrets/dkim/selector.txt")
        }
        pubIP := readSecret("/tmp/pmta-secrets/ip/public_ip.txt")

        cmd := exec.Command("bash", script("09-write_configs.sh"))
        cmd.Env = append(os.Environ(),
            "DOMAIN="+*domain,
            "HOSTNAME="+*hostname,
            "SMTP_USER="+*smtpUser,
            "SMTP_PASS="+*smtpPass,
            "SELECTOR="+sel,
            "PUBLIC_IP="+pubIP,
        )
        cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
        return cmd.Run()
    })

    run("configure_firewall", func() error {
        return exec.Command("bash", script("10-configure_firewall.sh")).Run()
    })

    run("check_ports", func() error {
        return exec.Command("bash", script("11-check_ports.sh")).Run()
    })

    run("restart_pmta", func() error {
        return exec.Command("bash", script("12-restart_pmta.sh")).Run()
    })

    run("smtp_connectivity", func() error {
        return exec.Command("bash", script("13-smtp_connectivity.sh")).Run()
    })

    run("cleanup", func() error {
        return exec.Command("bash", script("14-cleanup.sh")).Run()
    })

    fmt.Println("🎉 部署成功！SMTP 主机名:", *hostname)
    fmt.Println("    SMTP 用户名:", *smtpUser)
    fmt.Println("    SMTP 密码:", *smtpPass)
    fmt.Println("    可用端口: 25, 465, 587")
    fmt.Println("请为 PUBLIC_IP 设置 PTR 反向解析！")
}

func readSecret(path string) string {
    data, err := os.ReadFile(filepath.Clean(path))
    if err != nil {
        fmt.Fprintf(os.Stderr, "读取 %s 失败: %v\n", path, err)
        os.Exit(1)
    }
    return string(bytes.TrimSpace(data))
}
