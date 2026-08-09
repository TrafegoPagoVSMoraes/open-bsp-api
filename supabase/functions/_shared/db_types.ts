export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  billing: {
    Tables: {
      accounts: {
        Row: {
          created_at: string
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      costs: {
        Row: {
          created_at: string
          effective_at: string
          pricing: Json
          product: string
          provider: string
          quantity: number
          unit: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          effective_at?: string
          pricing: Json
          product: string
          provider: string
          quantity: number
          unit: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          effective_at?: string
          pricing?: Json
          product?: string
          provider?: string
          quantity?: number
          unit?: string
          updated_at?: string
        }
        Relationships: []
      }
      invoices: {
        Row: {
          created_at: string
          id: string
          organization_id: string
          period_end: string | null
          period_start: string | null
          status: string
          subtotal: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          organization_id: string
          period_end?: string | null
          period_start?: string | null
          status?: string
          subtotal?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          organization_id?: string
          period_end?: string | null
          period_start?: string | null
          status?: string
          subtotal?: number
          updated_at?: string
        }
        Relationships: []
      }
      invoices_items: {
        Row: {
          amount: number
          created_at: string
          id: string
          invoice_id: string
          ledger_id: string | null
          plan_id: string | null
          product_id: string | null
          quantity: number
          type: string
          unit_price: number
          updated_at: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          invoice_id: string
          ledger_id?: string | null
          plan_id?: string | null
          product_id?: string | null
          quantity: number
          type: string
          unit_price: number
          updated_at?: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          invoice_id?: string
          ledger_id?: string | null
          plan_id?: string | null
          product_id?: string | null
          quantity?: number
          type?: string
          unit_price?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoices_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_items_ledger_id_fkey"
            columns: ["ledger_id"]
            isOneToOne: false
            referencedRelation: "ledger"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_items_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      ledger: {
        Row: {
          agent_id: string | null
          billable: boolean | null
          created_at: string
          id: string
          message_id: string | null
          metadata: Json | null
          model: string | null
          organization_id: string
          product_id: string
          provider: string | null
          quantity: number
          type: string
          updated_at: string
        }
        Insert: {
          agent_id?: string | null
          billable?: boolean | null
          created_at?: string
          id?: string
          message_id?: string | null
          metadata?: Json | null
          model?: string | null
          organization_id: string
          product_id: string
          provider?: string | null
          quantity: number
          type: string
          updated_at?: string
        }
        Update: {
          agent_id?: string | null
          billable?: boolean | null
          created_at?: string
          id?: string
          message_id?: string | null
          metadata?: Json | null
          model?: string | null
          organization_id?: string
          product_id?: string
          provider?: string | null
          quantity?: number
          type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ledger_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          account_id: string | null
          amount: number
          created_at: string
          external_id: string | null
          id: string
          invoice_id: string
          method: string | null
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          account_id?: string | null
          amount: number
          created_at?: string
          external_id?: string | null
          id?: string
          invoice_id: string
          method?: string | null
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          account_id?: string | null
          amount?: number
          created_at?: string
          external_id?: string | null
          id?: string
          invoice_id?: string
          method?: string | null
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      plans: {
        Row: {
          active: boolean
          billing_cycle: string | null
          created_at: string
          id: string
          is_default: boolean
          min_tier: number
          price: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          billing_cycle?: string | null
          created_at?: string
          id: string
          is_default?: boolean
          min_tier: number
          price: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          billing_cycle?: string | null
          created_at?: string
          id?: string
          is_default?: boolean
          min_tier?: number
          price?: number
          updated_at?: string
        }
        Relationships: []
      }
      plans_products: {
        Row: {
          created_at: string
          included: number | null
          interval: string
          plan_id: string
          product_id: string
          unit_price: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          included?: number | null
          interval: string
          plan_id: string
          product_id: string
          unit_price?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          included?: number | null
          interval?: string
          plan_id?: string
          product_id?: string
          unit_price?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "plans_products_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plans_products_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          created_at: string
          id: string
          kind: string
          name: string
          unit: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id: string
          kind: string
          name: string
          unit: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: string
          name?: string
          unit?: string
          updated_at?: string
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          account_id: string | null
          created_at: string
          current_period_end: string | null
          current_period_start: string | null
          organization_id: string
          plan_id: string | null
          tier_id: string
          updated_at: string
        }
        Insert: {
          account_id?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          organization_id: string
          plan_id?: string | null
          tier_id: string
          updated_at?: string
        }
        Update: {
          account_id?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          organization_id?: string
          plan_id?: string | null
          tier_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_tier_id_fkey"
            columns: ["tier_id"]
            isOneToOne: false
            referencedRelation: "tiers"
            referencedColumns: ["id"]
          },
        ]
      }
      tiers: {
        Row: {
          active: boolean
          created_at: string
          id: string
          level: number
          name: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id: string
          level?: number
          name: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          level?: number
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      tiers_products: {
        Row: {
          cap: number | null
          created_at: string
          interval: string
          product_id: string
          tier_id: string
          updated_at: string
        }
        Insert: {
          cap?: number | null
          created_at?: string
          interval: string
          product_id: string
          tier_id: string
          updated_at?: string
        }
        Update: {
          cap?: number | null
          created_at?: string
          interval?: string
          product_id?: string
          tier_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tiers_products_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tiers_products_tier_id_fkey"
            columns: ["tier_id"]
            isOneToOne: false
            referencedRelation: "tiers"
            referencedColumns: ["id"]
          },
        ]
      }
      usage: {
        Row: {
          created_at: string
          interval: string
          organization_id: string
          period: string
          product_id: string
          quantity: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          interval?: string
          organization_id: string
          period?: string
          product_id: string
          quantity?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          interval?: string
          organization_id?: string
          period?: string
          product_id?: string
          quantity?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "usage_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      change_plan: {
        Args: { _organization_id: string; _plan_id: string }
        Returns: undefined
      }
      check_limit: {
        Args: {
          _amount?: number
          _organization_id: string
          _product_id: string
        }
        Returns: boolean
      }
      update_usage: {
        Args: {
          _organization_id: string
          _product_id: string
          _quantity?: number
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      agents: {
        Row: {
          ai: boolean
          created_at: string
          extra: Json | null
          id: string
          name: string
          organization_id: string
          picture: string | null
          updated_at: string
          user_id: string | null
        }
        Insert: {
          ai: boolean
          created_at?: string
          extra?: Json | null
          id?: string
          name: string
          organization_id: string
          picture?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          ai?: boolean
          created_at?: string
          extra?: Json | null
          id?: string
          name?: string
          organization_id?: string
          picture?: string | null
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agents_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      api_keys: {
        Row: {
          created_at: string
          id: string
          key: string
          name: string
          organization_id: string
          role: Database["public"]["Enums"]["role"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          key: string
          name: string
          organization_id: string
          role?: Database["public"]["Enums"]["role"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          key?: string
          name?: string
          organization_id?: string
          role?: Database["public"]["Enums"]["role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "api_keys_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      contacts: {
        Row: {
          created_at: string
          email: string | null
          extra: Json | null
          id: string
          name: string | null
          organization_id: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          email?: string | null
          extra?: Json | null
          id?: string
          name?: string | null
          organization_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          email?: string | null
          extra?: Json | null
          id?: string
          name?: string | null
          organization_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contacts_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      contacts_addresses: {
        Row: {
          address: string
          contact_id: string | null
          created_at: string
          extra: Json | null
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status: string
          updated_at: string
        }
        Insert: {
          address: string
          contact_id?: string | null
          created_at?: string
          extra?: Json | null
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status?: string
          updated_at?: string
        }
        Update: {
          address?: string
          contact_id?: string | null
          created_at?: string
          extra?: Json | null
          organization_id?: string
          service?: Database["public"]["Enums"]["service"]
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "contacts_addresses_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contacts_addresses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          contact_address: string | null
          created_at: string
          extra: Json | null
          group_address: string | null
          id: string
          name: string | null
          organization_address: string
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status: string
          updated_at: string
        }
        Insert: {
          contact_address?: string | null
          created_at?: string
          extra?: Json | null
          group_address?: string | null
          id?: string
          name?: string | null
          organization_address: string
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status?: string
          updated_at?: string
        }
        Update: {
          contact_address?: string | null
          created_at?: string
          extra?: Json | null
          group_address?: string | null
          id?: string
          name?: string | null
          organization_address?: string
          organization_id?: string
          service?: Database["public"]["Enums"]["service"]
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_contact_address_fkey"
            columns: ["organization_id", "service", "contact_address"]
            isOneToOne: false
            referencedRelation: "contacts_addresses"
            referencedColumns: ["organization_id", "service", "address"]
          },
          {
            foreignKeyName: "conversations_organization_address_fkey"
            columns: ["organization_id", "organization_address"]
            isOneToOne: false
            referencedRelation: "organizations_addresses"
            referencedColumns: ["organization_id", "address"]
          },
          {
            foreignKeyName: "conversations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      logs: {
        Row: {
          category: string
          created_at: string
          id: string
          level: Database["public"]["Enums"]["log_level"]
          message: string
          metadata: Json | null
          organization_address: string | null
          organization_id: string
          service: Database["public"]["Enums"]["service"] | null
        }
        Insert: {
          category: string
          created_at?: string
          id?: string
          level: Database["public"]["Enums"]["log_level"]
          message: string
          metadata?: Json | null
          organization_address?: string | null
          organization_id: string
          service?: Database["public"]["Enums"]["service"] | null
        }
        Update: {
          category?: string
          created_at?: string
          id?: string
          level?: Database["public"]["Enums"]["log_level"]
          message?: string
          metadata?: Json | null
          organization_address?: string | null
          organization_id?: string
          service?: Database["public"]["Enums"]["service"] | null
        }
        Relationships: [
          {
            foreignKeyName: "logs_organization_address_fkey"
            columns: ["organization_id", "organization_address"]
            isOneToOne: false
            referencedRelation: "organizations_addresses"
            referencedColumns: ["organization_id", "address"]
          },
          {
            foreignKeyName: "logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          agent_id: string | null
          contact_address: string | null
          content: Json
          conversation_id: string
          created_at: string
          direction: Database["public"]["Enums"]["direction"]
          external_id: string | null
          group_address: string | null
          id: string
          organization_address: string
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status: Json
          thread_id: string | null
          timestamp: string
          updated_at: string
        }
        Insert: {
          agent_id?: string | null
          contact_address?: string | null
          content: Json
          conversation_id: string
          created_at?: string
          direction: Database["public"]["Enums"]["direction"]
          external_id?: string | null
          group_address?: string | null
          id?: string
          organization_address: string
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status?: Json
          thread_id?: string | null
          timestamp?: string
          updated_at?: string
        }
        Update: {
          agent_id?: string | null
          contact_address?: string | null
          content?: Json
          conversation_id?: string
          created_at?: string
          direction?: Database["public"]["Enums"]["direction"]
          external_id?: string | null
          group_address?: string | null
          id?: string
          organization_address?: string
          organization_id?: string
          service?: Database["public"]["Enums"]["service"]
          status?: Json
          thread_id?: string | null
          timestamp?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_agent_id_fkey"
            columns: ["agent_id"]
            isOneToOne: false
            referencedRelation: "agents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      onboarding_tokens: {
        Row: {
          callback_url: string | null
          created_at: string
          expires_at: string
          id: string
          name: string
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status: string
          used_at: string | null
          verify_token: string | null
        }
        Insert: {
          callback_url?: string | null
          created_at?: string
          expires_at: string
          id?: string
          name: string
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status?: string
          used_at?: string | null
          verify_token?: string | null
        }
        Update: {
          callback_url?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          name?: string
          organization_id?: string
          service?: Database["public"]["Enums"]["service"]
          status?: string
          used_at?: string | null
          verify_token?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "onboarding_tokens_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          extra: Json | null
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          extra?: Json | null
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          extra?: Json | null
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      organizations_addresses: {
        Row: {
          address: string
          created_at: string
          extra: Json | null
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status: string
          updated_at: string
        }
        Insert: {
          address: string
          created_at?: string
          extra?: Json | null
          organization_id: string
          service: Database["public"]["Enums"]["service"]
          status?: string
          updated_at?: string
        }
        Update: {
          address?: string
          created_at?: string
          extra?: Json | null
          organization_id?: string
          service?: Database["public"]["Enums"]["service"]
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organizations_addresses_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      quick_replies: {
        Row: {
          content: string
          created_at: string
          id: string
          name: string
          organization_id: string
          updated_at: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          name: string
          organization_id: string
          updated_at?: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quick_replies_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tracking_events: {
        Row: {
          accept_language: string | null
          browser_family: string | null
          classification: Database["public"]["Enums"]["tracking_classification"]
          country: string | null
          device_type: string | null
          element_id: string | null
          event_id: string
          event_name: string
          event_type: Database["public"]["Enums"]["tracking_event_type"]
          id: string
          message_id: string | null
          metadata: Json
          occurred_at: string
          organization_id: string
          os_family: string | null
          page_path: string | null
          project_id: string
          received_at: string
          referer: string | null
          region: string | null
          request_id: string | null
          tracking_link_id: string | null
          tracking_session_id: string | null
        }
        Insert: {
          accept_language?: string | null
          browser_family?: string | null
          classification?: Database["public"]["Enums"]["tracking_classification"]
          country?: string | null
          device_type?: string | null
          element_id?: string | null
          event_id: string
          event_name: string
          event_type: Database["public"]["Enums"]["tracking_event_type"]
          id?: string
          message_id?: string | null
          metadata?: Json
          occurred_at: string
          organization_id: string
          os_family?: string | null
          page_path?: string | null
          project_id: string
          received_at?: string
          referer?: string | null
          region?: string | null
          request_id?: string | null
          tracking_link_id?: string | null
          tracking_session_id?: string | null
        }
        Update: {
          accept_language?: string | null
          browser_family?: string | null
          classification?: Database["public"]["Enums"]["tracking_classification"]
          country?: string | null
          device_type?: string | null
          element_id?: string | null
          event_id?: string
          event_name?: string
          event_type?: Database["public"]["Enums"]["tracking_event_type"]
          id?: string
          message_id?: string | null
          metadata?: Json
          occurred_at?: string
          organization_id?: string
          os_family?: string | null
          page_path?: string | null
          project_id?: string
          received_at?: string
          referer?: string | null
          region?: string | null
          request_id?: string | null
          tracking_link_id?: string | null
          tracking_session_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tracking_events_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_events_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_events_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "tracking_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_events_tracking_link_id_fkey"
            columns: ["tracking_link_id"]
            isOneToOne: false
            referencedRelation: "tracking_links"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_events_tracking_session_id_fkey"
            columns: ["tracking_session_id"]
            isOneToOne: false
            referencedRelation: "tracking_sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      tracking_links: {
        Row: {
          attribution: Json
          created_at: string
          destination_url: string
          disabled_at: string | null
          expires_at: string
          first_opened_at: string | null
          id: string
          idempotency_key: string
          last_opened_at: string | null
          message_id: string | null
          organization_id: string
          project_id: string
          source: string
          token_hash: string
          updated_at: string
        }
        Insert: {
          attribution?: Json
          created_at?: string
          destination_url: string
          disabled_at?: string | null
          expires_at: string
          first_opened_at?: string | null
          id?: string
          idempotency_key: string
          last_opened_at?: string | null
          message_id?: string | null
          organization_id: string
          project_id: string
          source?: string
          token_hash: string
          updated_at?: string
        }
        Update: {
          attribution?: Json
          created_at?: string
          destination_url?: string
          disabled_at?: string | null
          expires_at?: string
          first_opened_at?: string | null
          id?: string
          idempotency_key?: string
          last_opened_at?: string | null
          message_id?: string | null
          organization_id?: string
          project_id?: string
          source?: string
          token_hash?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tracking_links_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_links_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_links_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "tracking_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      tracking_projects: {
        Row: {
          allowed_origins: string[]
          created_at: string
          default_destination_url: string | null
          direct_session_rate_limit_per_minute: number
          id: string
          metadata: Json
          name: string
          organization_id: string
          public_key: string
          retention_days: number
          session_ttl_minutes: number
          slug: string
          status: string
          updated_at: string
        }
        Insert: {
          allowed_origins: string[]
          created_at?: string
          default_destination_url?: string | null
          direct_session_rate_limit_per_minute?: number
          id?: string
          metadata?: Json
          name: string
          organization_id: string
          public_key?: string
          retention_days?: number
          session_ttl_minutes?: number
          slug: string
          status?: string
          updated_at?: string
        }
        Update: {
          allowed_origins?: string[]
          created_at?: string
          default_destination_url?: string | null
          direct_session_rate_limit_per_minute?: number
          id?: string
          metadata?: Json
          name?: string
          organization_id?: string
          public_key?: string
          retention_days?: number
          session_ttl_minutes?: number
          slug?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tracking_projects_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      tracking_sessions: {
        Row: {
          created_at: string
          event_count: number
          expires_at: string
          id: string
          last_seen_at: string
          message_id: string | null
          organization_id: string
          origin: string
          project_id: string
          revoked_at: string | null
          session_token_hash: string
          tracking_link_id: string | null
        }
        Insert: {
          created_at?: string
          event_count?: number
          expires_at: string
          id?: string
          last_seen_at?: string
          message_id?: string | null
          organization_id: string
          origin: string
          project_id: string
          revoked_at?: string | null
          session_token_hash: string
          tracking_link_id?: string | null
        }
        Update: {
          created_at?: string
          event_count?: number
          expires_at?: string
          id?: string
          last_seen_at?: string
          message_id?: string | null
          organization_id?: string
          origin?: string
          project_id?: string
          revoked_at?: string | null
          session_token_hash?: string
          tracking_link_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "tracking_sessions_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_sessions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_sessions_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "tracking_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tracking_sessions_tracking_link_id_fkey"
            columns: ["tracking_link_id"]
            isOneToOne: false
            referencedRelation: "tracking_links"
            referencedColumns: ["id"]
          },
        ]
      }
      webhooks: {
        Row: {
          created_at: string
          id: string
          operations: Database["public"]["Enums"]["webhook_operation"][]
          organization_id: string
          table_name: Database["public"]["Enums"]["webhook_table"]
          token: string | null
          updated_at: string
          url: string
        }
        Insert: {
          created_at?: string
          id?: string
          operations: Database["public"]["Enums"]["webhook_operation"][]
          organization_id: string
          table_name: Database["public"]["Enums"]["webhook_table"]
          token?: string | null
          updated_at?: string
          url: string
        }
        Update: {
          created_at?: string
          id?: string
          operations?: Database["public"]["Enums"]["webhook_operation"][]
          organization_id?: string
          table_name?: Database["public"]["Enums"]["webhook_table"]
          token?: string | null
          updated_at?: string
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhooks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_click_events: {
        Row: {
          clicked_at: string
          id: number
          link_id: string
          user_agent: string | null
        }
        Insert: {
          clicked_at?: string
          id?: never
          link_id: string
          user_agent?: string | null
        }
        Update: {
          clicked_at?: string
          id?: never
          link_id?: string
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whatsapp_click_events_link_id_fkey"
            columns: ["link_id"]
            isOneToOne: false
            referencedRelation: "whatsapp_click_links"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_click_links: {
        Row: {
          campaign: string
          created_at: string
          destination_url: string
          disabled_at: string | null
          expires_at: string | null
          id: string
          message_external_id: string | null
          recipient_reference: string | null
          token: string
        }
        Insert: {
          campaign: string
          created_at?: string
          destination_url: string
          disabled_at?: string | null
          expires_at?: string | null
          id?: string
          message_external_id?: string | null
          recipient_reference?: string | null
          token: string
        }
        Update: {
          campaign?: string
          created_at?: string
          destination_url?: string
          disabled_at?: string | null
          expires_at?: string | null
          id?: string
          message_external_id?: string | null
          recipient_reference?: string | null
          token?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      agent_update_by_owner_rules: {
        Args: {
          p_ai: boolean
          p_extra: Json
          p_id: string
          p_organization_id: string
          p_user_id: string
        }
        Returns: boolean
      }
      cleanup_tracking_data: { Args: never; Returns: Json }
      contact_address_update_rules: {
        Args: {
          p_address: string
          p_extra: Json
          p_organization_id: string
          p_service: Database["public"]["Enums"]["service"]
          p_status: string
        }
        Returns: boolean
      }
      create_tracking_link: {
        Args: {
          p_attribution?: Json
          p_destination_url: string
          p_expires_at: string
          p_idempotency_key: string
          p_message_id?: string
          p_organization_id: string
          p_project_id: string
          p_source?: string
          p_token_hash: string
        }
        Returns: {
          created: boolean
          link_expires_at: string
          token_matches: boolean
          tracking_link_id: string
        }[]
      }
      create_tracking_session: {
        Args: {
          p_event_count: number
          p_origin: string
          p_public_key: string
          p_session_token_hash: string
        }
        Returns: {
          expires_at: string
          organization_id: string
          project_id: string
          tracking_session_id: string
        }[]
      }
      get_authorized_orgs: {
        Args: { role?: Database["public"]["Enums"]["role"] }
        Returns: string[]
      }
      get_tracking_dashboard: {
        Args: {
          p_from?: string
          p_organization_id: string
          p_project_id?: string
          p_to?: string
        }
        Returns: Json
      }
      init_data: {
        Args: {
          p_limit?: number
          p_organization_id: string
          p_per_conversation?: number
          p_since?: string
          p_until?: string
        }
        Returns: Json
      }
      member_self_update_rules: {
        Args: {
          p_ai: boolean
          p_extra: Json
          p_id: string
          p_organization_id: string
          p_user_id: string
        }
        Returns: boolean
      }
      merge_update_jsonb: {
        Args: { object: Json; path: string[]; target: Json }
        Returns: Json
      }
      org_update_by_admin_rules: {
        Args: { p_id: string; p_name: string }
        Returns: boolean
      }
      record_tracking_open: {
        Args: {
          p_accept_language?: string
          p_browser_family?: string
          p_classification: Database["public"]["Enums"]["tracking_classification"]
          p_country?: string
          p_device_type?: string
          p_event_id: string
          p_occurred_at: string
          p_os_family?: string
          p_referer?: string
          p_region?: string
          p_request_id?: string
          p_session_token_hash: string
          p_token_hash: string
        }
        Returns: {
          destination_url: string
          message_id: string
          organization_id: string
          project_id: string
          tracking_link_id: string
          tracking_session_id: string
        }[]
      }
      reserve_tracking_session: {
        Args: {
          p_event_count: number
          p_origin: string
          p_session_token_hash: string
        }
        Returns: {
          event_count: number
          expires_at: string
          message_id: string
          organization_id: string
          project_id: string
          session_origin: string
          tracking_link_id: string
          tracking_session_id: string
        }[]
      }
    }
    Enums: {
      direction: "incoming" | "outgoing" | "internal"
      log_level: "info" | "warning" | "error"
      role: "owner" | "admin" | "member"
      service:
        | "whatsapp"
        | "instagram"
        | "local"
        | "slack"
        | "discord"
        | "teams"
        | "whatsapp-web"
      tracking_classification:
        | "human_candidate"
        | "bot"
        | "preview"
        | "prefetch"
        | "unknown"
      tracking_event_type:
        | "link_open"
        | "page_view"
        | "click"
        | "form_start"
        | "form_submit"
        | "conversion"
        | "custom"
      webhook_operation: "insert" | "update"
      webhook_table:
        | "messages"
        | "conversations"
        | "organizations_addresses"
        | "contacts"
        | "contacts_addresses"
        | "logs"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  storage: {
    Tables: {
      buckets: {
        Row: {
          allowed_mime_types: string[] | null
          avif_autodetection: boolean | null
          created_at: string | null
          file_size_limit: number | null
          id: string
          name: string
          owner: string | null
          owner_id: string | null
          public: boolean | null
          type: Database["storage"]["Enums"]["buckettype"]
          updated_at: string | null
        }
        Insert: {
          allowed_mime_types?: string[] | null
          avif_autodetection?: boolean | null
          created_at?: string | null
          file_size_limit?: number | null
          id: string
          name: string
          owner?: string | null
          owner_id?: string | null
          public?: boolean | null
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string | null
        }
        Update: {
          allowed_mime_types?: string[] | null
          avif_autodetection?: boolean | null
          created_at?: string | null
          file_size_limit?: number | null
          id?: string
          name?: string
          owner?: string | null
          owner_id?: string | null
          public?: boolean | null
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string | null
        }
        Relationships: []
      }
      buckets_analytics: {
        Row: {
          created_at: string
          deleted_at: string | null
          format: string
          id: string
          name: string
          type: Database["storage"]["Enums"]["buckettype"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          format?: string
          id?: string
          name: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          format?: string
          id?: string
          name?: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Relationships: []
      }
      buckets_vectors: {
        Row: {
          created_at: string
          id: string
          type: Database["storage"]["Enums"]["buckettype"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          type?: Database["storage"]["Enums"]["buckettype"]
          updated_at?: string
        }
        Relationships: []
      }
      iceberg_namespaces: {
        Row: {
          bucket_name: string
          catalog_id: string
          created_at: string
          id: string
          metadata: Json
          name: string
          updated_at: string
        }
        Insert: {
          bucket_name: string
          catalog_id: string
          created_at?: string
          id?: string
          metadata?: Json
          name: string
          updated_at?: string
        }
        Update: {
          bucket_name?: string
          catalog_id?: string
          created_at?: string
          id?: string
          metadata?: Json
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "iceberg_namespaces_catalog_id_fkey"
            columns: ["catalog_id"]
            isOneToOne: false
            referencedRelation: "buckets_analytics"
            referencedColumns: ["id"]
          },
        ]
      }
      iceberg_tables: {
        Row: {
          bucket_name: string
          catalog_id: string
          created_at: string
          id: string
          location: string
          name: string
          namespace_id: string
          remote_table_id: string | null
          shard_id: string | null
          shard_key: string | null
          updated_at: string
        }
        Insert: {
          bucket_name: string
          catalog_id: string
          created_at?: string
          id?: string
          location: string
          name: string
          namespace_id: string
          remote_table_id?: string | null
          shard_id?: string | null
          shard_key?: string | null
          updated_at?: string
        }
        Update: {
          bucket_name?: string
          catalog_id?: string
          created_at?: string
          id?: string
          location?: string
          name?: string
          namespace_id?: string
          remote_table_id?: string | null
          shard_id?: string | null
          shard_key?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "iceberg_tables_catalog_id_fkey"
            columns: ["catalog_id"]
            isOneToOne: false
            referencedRelation: "buckets_analytics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "iceberg_tables_namespace_id_fkey"
            columns: ["namespace_id"]
            isOneToOne: false
            referencedRelation: "iceberg_namespaces"
            referencedColumns: ["id"]
          },
        ]
      }
      migrations: {
        Row: {
          executed_at: string | null
          hash: string
          id: number
          name: string
        }
        Insert: {
          executed_at?: string | null
          hash: string
          id: number
          name: string
        }
        Update: {
          executed_at?: string | null
          hash?: string
          id?: number
          name?: string
        }
        Relationships: []
      }
      objects: {
        Row: {
          bucket_id: string | null
          created_at: string | null
          id: string
          last_accessed_at: string | null
          metadata: Json | null
          name: string | null
          owner: string | null
          owner_id: string | null
          path_tokens: string[] | null
          updated_at: string | null
          user_metadata: Json | null
          version: string | null
        }
        Insert: {
          bucket_id?: string | null
          created_at?: string | null
          id?: string
          last_accessed_at?: string | null
          metadata?: Json | null
          name?: string | null
          owner?: string | null
          owner_id?: string | null
          path_tokens?: string[] | null
          updated_at?: string | null
          user_metadata?: Json | null
          version?: string | null
        }
        Update: {
          bucket_id?: string | null
          created_at?: string | null
          id?: string
          last_accessed_at?: string | null
          metadata?: Json | null
          name?: string | null
          owner?: string | null
          owner_id?: string | null
          path_tokens?: string[] | null
          updated_at?: string | null
          user_metadata?: Json | null
          version?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "objects_bucketId_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets"
            referencedColumns: ["id"]
          },
        ]
      }
      s3_multipart_uploads: {
        Row: {
          bucket_id: string
          created_at: string
          id: string
          in_progress_size: number
          key: string
          metadata: Json | null
          owner_id: string | null
          upload_signature: string
          user_metadata: Json | null
          version: string
        }
        Insert: {
          bucket_id: string
          created_at?: string
          id: string
          in_progress_size?: number
          key: string
          metadata?: Json | null
          owner_id?: string | null
          upload_signature: string
          user_metadata?: Json | null
          version: string
        }
        Update: {
          bucket_id?: string
          created_at?: string
          id?: string
          in_progress_size?: number
          key?: string
          metadata?: Json | null
          owner_id?: string | null
          upload_signature?: string
          user_metadata?: Json | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "s3_multipart_uploads_bucket_id_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets"
            referencedColumns: ["id"]
          },
        ]
      }
      s3_multipart_uploads_parts: {
        Row: {
          bucket_id: string
          created_at: string
          etag: string
          id: string
          key: string
          owner_id: string | null
          part_number: number
          size: number
          upload_id: string
          version: string
        }
        Insert: {
          bucket_id: string
          created_at?: string
          etag: string
          id?: string
          key: string
          owner_id?: string | null
          part_number: number
          size?: number
          upload_id: string
          version: string
        }
        Update: {
          bucket_id?: string
          created_at?: string
          etag?: string
          id?: string
          key?: string
          owner_id?: string | null
          part_number?: number
          size?: number
          upload_id?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "s3_multipart_uploads_parts_bucket_id_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "s3_multipart_uploads_parts_upload_id_fkey"
            columns: ["upload_id"]
            isOneToOne: false
            referencedRelation: "s3_multipart_uploads"
            referencedColumns: ["id"]
          },
        ]
      }
      vector_indexes: {
        Row: {
          bucket_id: string
          created_at: string
          data_type: string
          dimension: number
          distance_metric: string
          id: string
          metadata_configuration: Json | null
          name: string
          updated_at: string
        }
        Insert: {
          bucket_id: string
          created_at?: string
          data_type: string
          dimension: number
          distance_metric: string
          id?: string
          metadata_configuration?: Json | null
          name: string
          updated_at?: string
        }
        Update: {
          bucket_id?: string
          created_at?: string
          data_type?: string
          dimension?: number
          distance_metric?: string
          id?: string
          metadata_configuration?: Json | null
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "vector_indexes_bucket_id_fkey"
            columns: ["bucket_id"]
            isOneToOne: false
            referencedRelation: "buckets_vectors"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      allow_any_operation: {
        Args: { expected_operations: string[] }
        Returns: boolean
      }
      allow_only_operation: {
        Args: { expected_operation: string }
        Returns: boolean
      }
      can_insert_object: {
        Args: { bucketid: string; metadata: Json; name: string; owner: string }
        Returns: undefined
      }
      extension: { Args: { name: string }; Returns: string }
      filename: { Args: { name: string }; Returns: string }
      foldername: { Args: { name: string }; Returns: string[] }
      get_common_prefix: {
        Args: { p_delimiter: string; p_key: string; p_prefix: string }
        Returns: string
      }
      get_size_by_bucket: {
        Args: never
        Returns: {
          bucket_id: string
          size: number
        }[]
      }
      list_multipart_uploads_with_delimiter: {
        Args: {
          bucket_id: string
          delimiter_param: string
          max_keys?: number
          next_key_token?: string
          next_upload_token?: string
          prefix_param: string
        }
        Returns: {
          created_at: string
          id: string
          key: string
        }[]
      }
      list_objects_with_delimiter: {
        Args: {
          _bucket_id: string
          delimiter_param: string
          max_keys?: number
          next_token?: string
          prefix_param: string
          sort_order?: string
          start_after?: string
        }
        Returns: {
          created_at: string
          id: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
      operation: { Args: never; Returns: string }
      search: {
        Args: {
          bucketname: string
          levels?: number
          limits?: number
          offsets?: number
          prefix: string
          search?: string
          sortcolumn?: string
          sortorder?: string
        }
        Returns: {
          created_at: string
          id: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
      search_by_timestamp: {
        Args: {
          p_bucket_id: string
          p_level: number
          p_limit: number
          p_prefix: string
          p_sort_column: string
          p_sort_column_after: string
          p_sort_order: string
          p_start_after: string
        }
        Returns: {
          created_at: string
          id: string
          key: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
      search_v2: {
        Args: {
          bucket_name: string
          levels?: number
          limits?: number
          prefix: string
          sort_column?: string
          sort_column_after?: string
          sort_order?: string
          start_after?: string
        }
        Returns: {
          created_at: string
          id: string
          key: string
          last_accessed_at: string
          metadata: Json
          name: string
          updated_at: string
        }[]
      }
    }
    Enums: {
      buckettype: "STANDARD" | "ANALYTICS" | "VECTOR"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  billing: {
    Enums: {},
  },
  public: {
    Enums: {
      direction: ["incoming", "outgoing", "internal"],
      log_level: ["info", "warning", "error"],
      role: ["owner", "admin", "member"],
      service: [
        "whatsapp",
        "instagram",
        "local",
        "slack",
        "discord",
        "teams",
        "whatsapp-web",
      ],
      tracking_classification: [
        "human_candidate",
        "bot",
        "preview",
        "prefetch",
        "unknown",
      ],
      tracking_event_type: [
        "link_open",
        "page_view",
        "click",
        "form_start",
        "form_submit",
        "conversion",
        "custom",
      ],
      webhook_operation: ["insert", "update"],
      webhook_table: [
        "messages",
        "conversations",
        "organizations_addresses",
        "contacts",
        "contacts_addresses",
        "logs",
      ],
    },
  },
  storage: {
    Enums: {
      buckettype: ["STANDARD", "ANALYTICS", "VECTOR"],
    },
  },
} as const

