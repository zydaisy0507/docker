package steps

import (
    "embed"
    "fmt"
    "io/fs"
    "os"
    "path/filepath"
)

//go:embed assets/**
var FS embed.FS

// WriteAssets 将 embed 的资源目录写出到磁盘，并校验关键脚本和文件
func WriteAssets() error {
    target := "/tmp/assets"

    if err := os.MkdirAll(target, 0755); err != nil {
        return fmt.Errorf("创建目录 %s 失败: %w", target, err)
    }

    err := fs.WalkDir(FS, ".", func(path string, d fs.DirEntry, err error) error {
        if err != nil {
            fmt.Printf("❌ WalkDir 遍历错误: %v\n", err)
            return err
        }

        fmt.Printf("🟡 正在处理: %s\n", path)

        outPath := filepath.Join(target, path)
        if d.IsDir() {
            fmt.Printf("📁 创建目录: %s\n", outPath)
            return os.MkdirAll(outPath, 0755)
        }

        data, err := FS.ReadFile(path)
        if err != nil {
            fmt.Printf("❌ 读取文件失败: %s (%v)\n", path, err)
            return err
        }

        fmt.Printf("📄 写入文件: %s\n", outPath)
        if err := os.WriteFile(outPath, data, 0644); err != nil {
            fmt.Printf("❌ 写入失败: %s (%v)\n", outPath, err)
            return err
        }

        return nil
    })
    if err != nil {
        return err
    }

    // 校验并授权脚本
    scripts := []string{
        "01-system_update.sh",
        "02-write_assets.sh",
        "03-gen_dkim.sh",
        "04-get_public_ip.sh",
        "05-fetch_zone.sh",
        "06-update_dns.sh",
        "07-install_acme.sh",
        "deploy.sh",
        "08-install_pmta.sh",
        "09-write_configs.sh",
        "10-configure_firewall.sh",
        "11-check_ports.sh",
        "12-restart_pmta.sh",
        "13-smtp_connectivity.sh",
        "14-cleanup.sh",
    }

    for _, name := range scripts {
        scriptPath := filepath.Join(target, "assets/scripts", name)
        if info, err := os.Stat(scriptPath); err != nil {
            return fmt.Errorf("缺失脚本 %s: %w", scriptPath, err)
        } else if info.IsDir() {
            return fmt.Errorf("脚本路径不是文件 %s", scriptPath)
        }
        if err := os.Chmod(scriptPath, 0755); err != nil {
            return fmt.Errorf("设置脚本可执行权限失败 %s: %w", scriptPath, err)
        }
    }

    deb := filepath.Join(target, "assets/PowerMTA-5.0r8.deb")
    if _, err := os.Stat(deb); err != nil {
        return fmt.Errorf("缺失安装包 %s: %w", deb, err)
    }

    return nil
}
